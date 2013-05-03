########################################
  package  Net::Async::Omegle::Session #
# ------------------------------------ #
# A clean, non-blocking Perl interface #
# to Omegle.com for the IO::Async.     #
# http://github.com/cooper/new-omegle  #
#             ...and net-async-omegle. #
########################################
;
# Copyright (c) 2011-2013, Mitchell Cooper


use warnings;
use strict;
use 5.010;
use parent 'EventedObject';

use URI::Escape::XS 'encodeURIComponent';

our $VERSION = $Net::Async::Omegle::VERSION;

# create a new session object.
# typically, this is not used directly.
# $om->new() should be used instead.
sub new {
    my ($class, %opts) = @_;
    bless \%opts, $class;
}

# $sess->start()
# create a new Omegle session.
sub start {
    my $sess = shift;
    my $om   = $sess->{om} or return;
    $sess->{server} = $om->newserver;
    my $type = $sess->opt('type') || 'Traditional';
    
    # basic parameters.
    my $startopts = '?rcs=1&spid=';

    # we are a cell phone!
    $startopts .= '&m=1' if $sess->opt('mobile');

    # common interests mode.
    if ($type eq 'CommonInterests') {
        my $topics  = JSON::encode_json($sess->opt('topics'));
        $startopts .= '&topics='.encodeURIComponent($topics);
        $sess->{stopsearching} = time() + 5;
    }

    # ask mode.
    elsif ($type eq 'AskQuestion') {
        $startopts .= '&ask='.encodeURIComponent($sess->opt('question'));
    }

    # answer mode.
    elsif ($type eq 'AnswerQuestion') {
        $startopts .= '&wantsspy=1';
    }

    # start a session and get its client ID.
    $om->post("http://$$sess{server}/start$startopts", [], sub {
        shift() =~ m/^"(.+)"$/ or return;
        
        $sess->{omegle_id}  = $1;
        $om->{sessions}{$1} = $sess;

        # fire got_id event.
        $sess->fire(got_id => $1);

        # request the first event.
        $sess->request_next_event;
        
    });

    $sess->{running} = 1;

    return 1;
}

# $sess->submit_captcha($solution)
# submit recaptcha request.
sub submit_captcha {
    my ($sess, $response) = @_;
    $sess->post('recaptcha', [
        challenge => $sess->{challenge},
        response  => $response
    ]);
}

# $sess->say($message)
# send a message.
sub say {
    my ($sess, $msg) = @_;

    # session not established entirely
    return unless $sess->{connected};

    # spying session; can't talk
    return if $sess->{type} == 'AskQuestion';

    $sess->post('send', [ msg => $msg ]);
}

# $sess->type()
# make it appear that you are typing.
sub type {
    my $sess = shift;

    # session not established entirely
    return unless $sess->{connected};

    # spying session; can't talk
    return if $sess->{type} == 'AskQuestion';

    $sess->post('typing');
}

# $sess->stoptype()
# make it appear that you have stopped typing.
sub stoptype {
    my $sess = shift;

    # session not established entirely
    return unless $sess->{connected};

    # spying session; can't talk
    return if $sess->{type} == 'AskQuestion';

    $sess->post('stoptyping');
}

# $sess->disconnect()
# disconnect from Omegle.
sub disconnect {
    my $sess = shift;
    $sess->post('disconnect');
    $sess->done();
}

# clean up after a session ends.
sub done {
    my $sess = shift;
    $sess->{om}->remove_session($sess) if $sess->{om};
    exists $sess->{$_} && delete $sess->{$_} foreach qw(
        running waiting connected omegle_id typing
        typing_1 typing_2 type challenge
    );
}

# handle an event from Omegle.
sub handle_event {
    my ($sess, $event_name, @event) = @_;
    my $om = $sess->{om} or return;

    # fire debug event.
    $sess->fire(debug => 'EVENT: '.$event_name.q[(].join(', ', @event).q[)]);

    # fire a raw event.
    $sess->fire("raw_$event_name" => @event);

    given ($event_name) {

        # status info update.
        when ('statusInfo') {
            $sess->{om}->_update_status($event[0]);
            # status_update called later.
        }

        # message from server.
        when ('serverMessage') {
            $sess->fire(server_message => $event[0]);
        }

        # waiting on a chatting partner.
        when ('waiting') {
            $sess->fire('waiting');
            $sess->{waiting} = 1;
        }

        # session established.
        when ('connected') {
            $sess->fire('connect');             # compat.
            $sess->fire('connected'); 
            $sess->{connected} = 1;
        }

        # stranger said something.
        when ('gotMessage') {
            $sess->fire(chat    => $event[0]); # compat.
            $sess->fire(message => $event[0]);
            delete $sess->{typing};
        }

        # stranger disconnected.
        when ('strangerDisconnected') {
            $sess->fire('disconnect');
            $sess->done;
        }

        # stranger is typing.
        when ('typing') {
            continue if $sess->opt('no_type');
            $sess->fire('type') unless $sess->{typing};
            $sess->{typing} = 1;
        }

        # stranger stopped typing.
        when ('stoppedTyping') {
            continue if $sess->opt('no_type');
            $sess->fire('stoptype') if $sess->{typing};
            delete $sess->{typing};
        }

        # stranger has similar interests.
        when ('commonLikes') {
            $sess->fire(commonlikes => $event[0]);
        }

        # question is asked.
        when ('question') {
            $sess->fire(question => $event[0]);
        }

        # spyee disconnected.
        when ('spyDisconnected') {
            my $which = $event[0];
            $which =~ s/Stranger //;
            $sess->fire(spydisconnect => $which);
            $sess->done;
        }

        # spyee is typing.
        when ('spyTyping') {
            continue if $sess->opt('no_type');
            my $which = $event[0];
            $which =~ s/Stranger //;
            $sess->fire(spytype => $which) unless $sess->{"typing_$which"};
            $sess->{"typing_$which"} = 1;
        }

        # spyee stopped typing.
        when ('spyStoppedTyping') {
            continue if $sess->opt('no_type');
            my $which = $event[0];
            $which =~ s/Stranger //;
            $sess->fire(spystoptype => $which) if $sess->{"typing_$which"};
            delete $sess->{"typing_$which"};
        }

        # spyee said something.
        when ('spyMessage') {
            my $which = $event[0];
            $which =~ s/Stranger //;
            $sess->fire(spychat => $which, $event[1]);
            delete $sess->{"typing_$which"};
        }

        # number of people online.
        # XXX: this event is obsolete due to statusInfo.
        # however, Omegle appears to still send it under certain circumstances.
        # for that reason, we will continue to handle it.
        when ('count') {
            $om->{online} = $event[0];
            
            # we fire this on the Omegle instance.
            $sess->{om}->fire(update_user_count => $event[0]);
            
        }

        # an error has occured, and the session must end.
        when ('error') {
            $sess->fire(error => $event[0]);
            $sess->done;
        }

        # captcha was rejected.
        when ('recaptchaRejected') {
            $sess->fire('badcaptcha');
            continue;
        }

        # server requests captcha.
        when (['recaptchaRequired', 'recaptchaRejected']) {
            $sess->fire(wantcaptcha => $event[0]);

            # ask reCAPTCHA for an image.
            $om->get("http://google.com/recaptcha/api/challenge?k=$event[0]&ajax=1", sub {
                my $data = shift;
                return unless $data =~ m/challenge : '(.+)'/;
                $sess->{challenge} = $1;

                # got it; fire the callback.
                $sess->fire(gotcaptcha => "http://www.google.com/recaptcha/api/image?c=$1");
            });
        }

        # other
        default {
            $sess->fire(debug => "unknown event: $event_name");
        }

    }

    return 1;
}

# parse events from Omegle.
sub handle_events {
    my ($sess, $data) = @_;

    # must be an array of events.
    return unless $data =~ m/^\[/;

    # event JSON
    my $events = JSON::decode_json($data);
    $sess->handle_event(@$_) foreach @$events;

    # request more events.
    $sess->request_next_event if $sess->{omegle_id};
}

# request an event from Omegle.
sub request_next_event {
    my $sess = shift;
    $sess->fire(debug => 'requesting next event.');
    $sess->post('events', [], \&handle_events, $sess);
}

# post to the session server with the 'id' variable.
sub post {
    my ($sess, $page, $vars, $callback, @args) = @_;
    my $om = $sess->{om} or return;
    $om->post("http://$$sess{server}/$page", [
        id => $sess->{omegle_id},
        @{ $vars || [] }
    ], $callback, @args);
}

# fire an event.
# this fires the event on the session object.
# it also fires the event on the Omegle object, using the session as the first argument.
sub fire {
    my ($sess, $event_name, @args) = @_;
    $sess->fire_event($event_name => @args);
    $sess->{om}->fire_event($event_name => $sess, @args) if $sess->{om};
    return 1;
}

# get an option, either from the session or from the Omegle instance.
sub opt {
    my ($sess, $opt) = @_;
    $sess->{$opt} || $sess->{om}{$opt}
}

# returns true if the session is running (/start request completed)
sub running {
    return shift->{running};
}

# returns true if the session is waiting (stranger not yet found)
sub waiting {
    return shift->{waiting};
}

# returns true if the session is connected (stranger found)
sub connected {
    return shift->{connected};
}

# returns the omegle session identifier.
sub id {
    return shift->{omegle_id};
}

# compat.
sub omegle_id;
*omegle_id = *id;

# returns true if the stranger is typing.
# in ask/answer modes, returns true if either stranger is typing.
sub stranger_typing {
    my $sess = shift;
    return $sess->{typing} || $sess->{typing_1} || $sess->{typing_2} || undef;
}

# returns the server this session is taking place on.
sub server {
    return shift->{server};
}

1
