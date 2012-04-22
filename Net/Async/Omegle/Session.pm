########################################
  package  Net::Async::Omegle::Session #
# ------------------------------------ #
# A clean, non-blocking Perl interface #
# to Omegle.com for the IO::Async.     #
# http://github.com/cooper/new-omegle  #
#             ...and net-async-omegle. #
########################################
;
# Copyright (c) 2011-2012, Mitchell Cooper
#
# session modes:
#    undef: no session
#    0: traditional
#    1: traditional + common likes submitted
#    2: spy mode (you're the spy)
#    3: spy mode (you're spied on)

use warnings;
use strict;
use 5.010;

use URI::Escape::XS 'encodeURIComponent';

our $VERSION = $Net::Async::Omegle::VERSION;

# session modes.
my %SESS = (
    NORMAL => 0,
    COMMON => 1,
    SPYER  => 2,
    SPYEE  => 3
);

# create a new session object.
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
    $sess->{type}   = $SESS{NORMAL};
    my $startopts   = '?rcs=1&spid=';

    # enable common interests.
    if ($sess->opt('use_likes')) {
        $startopts   .= '&topics='.encodeURIComponent($sess->opt('topics'));
        $sess->{type} = $SESS{COMMON};
        $sess->{stopsearching} = time() + 5;
    }

    # enable question mode.
    elsif ($sess->opt('use_question')) {
        $startopts   .= '&ask='.encodeURIComponent($sess->opt('question'));
        $sess->{type} = $SESS{SPYER};
    }

    # enable answer mode.
    elsif ($sess->opt('want_question')) {
        $startopts   .= '&wantsspy=1';
        $sess->{type} = $SESS{SPYEE};
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
    return if $sess->{type} == $SESS{SPYER};

    $sess->post('send', [ msg => $msg ]);
}

# $sess->type()
# make it appear that you are typing.
sub type {
    my $sess = shift;

    # session not established entirely
    return unless $sess->{connected};

    # spying session; can't talk
    return if $sess->{type} == $SESS{SPYER};

    $sess->post('typing');
}

# $sess->stoptype()
# make it appear that you have stopped typing.
sub stoptype {
    my $sess = shift;

    # session not established entirely
    return unless $sess->{connected};

    # spying session; can't talk
    return if $sess->{type} == $SESS{SPYER};

    $sess->post('stoptyping');
}

# clean up after a session ends.
sub done {
    my $sess = shift;
    delete $sess->{om}{sessions}{$sess->{omegle_id}} if $sess->{omegle_id};
    exists $sess->{$_} && delete $sess->{$_} foreach qw(
        connected omegle_id typing
        typing_1 typing_2 type challenge
    );
}

# handle an event from Omegle.
sub handle_event {
    my ($sess, $event, @event_args) = @_;
    my $om = $sess->{om} or return;

    # fire debug event.
    $sess->fire(debug => 'EVENT: '.$event.q[(].join(', ', @event_args).q[)]);

    given ($event) {

        # session established.
        when ('connected') {
            $sess->fire('connect');
            $sess->{connected} = 1;
        }

        # stranger said something.
        when ('gotMessage') {
            $sess->fire(chat => $event_args[0]);
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
            $sess->fire(commonlikes => $event_args[0]);
        }

        # question is asked.
        when ('question') {
            $sess->fire(question => $event_args[0]);
        }

        # spyee disconnected.
        when ('spyDisconnected') {
            my $which = $event_args[0];
            $which =~ s/Stranger //;
            $sess->fire(spydisconnect => $which);
            $sess->done;
        }

        # spyee is typing.
        when ('spyTyping') {
            continue if $sess->opt('no_type');
            my $which = $event_args[0];
            $which =~ s/Stranger //;
            $sess->fire(spytype => $which) unless $sess->{"typing_$which"};
            $sess->{"typing_$which"} = 1;
        }

        # spyee stopped typing.
        when ('spyStoppedTyping') {
            continue if $sess->opt('no_type');
            my $which = $event_args[0];
            $which =~ s/Stranger //;
            $sess->fire(spystoptype => $which) if $sess->{"typing_$which"};
            delete $sess->{"typing_$which"};
        }

        # spyee said something.
        when ('spyMessage') {
            my $which = $event_args[0];
            $which =~ s/Stranger //;
            $sess->fire(spychat => $which, $event_args[1]);
            delete $sess->{"typing_$which"};
        }

        # number of people online.
        when ('count') {
            $om->{online} = $event_args[0];
            $sess->fire(count => $event_args[0]);
        }

        # an error has occured and the session must end.
        when ('error') {
            $sess->fire(error => $event_args[0]);
            $sess->done;
        }

        # captcha was rejected.
        when ('recaptchaRejected') {
            $sess->fire('badcaptcha');
            continue;
        }

        # server requests captcha.
        when (['recaptchaRequired', 'recaptchaRejected']) {
            $sess->fire('wantcaptcha');

            # ask reCAPTCHA for an image.
            $om->get("http://google.com/recaptcha/api/challenge?k=$event_args[0]&ajax=1", sub {
                my $data = shift;
                return unless $data =~ m/challenge : '(.+)'/;
                $sess->{challenge} = $1;

                # got it; fire the callback.
                $sess->fire(gotcaptcha => "http://www.google.com/recaptcha/api/image?c=$1");
            });
        }

        # other
        default {
            $sess->fire(debug => "unknown event: $event");
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

# fire a callback.
sub fire {
    my ($sess, $callback, @args) = (shift, 'on_'.shift(), @_);
    $sess->{$callback}($sess, @args) if $sess->{$callback};
    $sess->{om}{opts}{$callback}($sess, @args) if $sess->{om}{opts}{$callback};

    # fire debug event.
    $sess->fire(debug => 'FIRE: '.$callback.q[(].join(', ', @args).q[)])
    unless $callback eq 'on_debug'; # do not want recursion!

    return 1;
}

# get an option, either from the session or from the Omegle instance.
sub opt {
    my ($sess, $opt) = @_;
    $sess->{$opt} || $sess->{om}{$opt}
}

1
