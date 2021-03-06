###############################################
  package Net::Async::Omegle::Session         ;
# ------------------------------------------- #
#                                             #
# A clean, non-blocking Perl interface to     #
# Omegle.com for the IO::Async event library. #
# http://github.com/cooper/net-async-omegle   #
#                                             #
#  Copyright (c) 2011-2014, Mitchell Cooper   #
#                                             #
###############################################

use warnings;
use strict;
use 5.010;
use parent 'Evented::Object';

use URI::Escape::XS 'encodeURIComponent';

our $VERSION = '5.16';

our $CAPTCHA_CHLNG = 'http://google.com/recaptcha/api/challenge?ajax=1&k=';
our $CAPTCHA_IMAGE = 'http://www.google.com/recaptcha/api/image?c=';

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
    my $om   = $sess->om or return;

    # we are already running?
    return if $sess->{running};

    $sess->{server} = $om->newserver;
    my $type = $sess->opt('type') || 'Traditional';

    # basic parameters.
    my $startopts = '?rcs=1&spid=';

    # we are a cell phone!
    $startopts .= '&m=1' if $sess->opt('mobile');

    # common interests mode.
    if ($type eq 'CommonInterests') {
        my $topics  = $sess->encode($sess->opt('topics'));
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
    $sess->fire('start');

    return 1;
}

# $sess->submit_captcha($solution)
# submit recaptcha request.
sub submit_captcha {
    my ($sess, $response) = @_;
    return unless $sess->{running};
    delete $sess->{waiting_for_captcha};
    $sess->post('recaptcha', [
        challenge => $sess->{challenge},
        response  => $response
    ]);
}

# $sess->say($message)
# send a message.
sub say : method {
    my ($sess, $msg) = @_;

    # session not established entirely
    return unless $sess->{connected};

    # spying session; can't talk
    return if $sess->opt('type') eq 'AskQuestion';

    # Safe point - we'll try to send the message.

    # stop typing and store the message ID.
    delete $sess->{im_typing};
    my $id = $sess->{message_id_counter}++;

    # 'win' means the message was sent successfully
    $sess->post('send', [ msg => $msg ], sub {
        my $content = shift;
        if ($content ne 'win') {
            $sess->debug("Bad response for message $id: $content");
            return;
        }
        $sess->debug("Message $id sent successfully.");
        $sess->fire(you_message => $msg, $id);
    });

    return $id;
}

# $sess->type()
# make it appear that you are typing.
sub type {
    my $sess = shift;

    # session not established entirely
    return unless $sess->{connected};

    # spying session; can't talk
    return if $sess->opt('type') eq 'AskQuestion';

    # already typing
    return if $sess->{im_typing};
    $sess->{im_typing}++;

    $sess->post('typing');
}

# $sess->stop_typing()
# make it appear that you have stopped typing.
sub stop_typing {
    my $sess = shift;

    # session not established entirely
    return unless $sess->{connected};

    # spying session; can't talk
    return if $sess->opt('type') eq 'AskQuestion';

    # not typing
    return unless $sess->{im_typing};
    delete $sess->{im_typing};

    $sess->post('stoptyping');
}

# compat.
sub stoptype { &stop_typing }

# $sess->disconnect()
# disconnect from Omegle.
sub disconnect {
    my $sess = shift;
    return unless $sess->{running};
    $sess->post('disconnect');
    $sess->done();
}

# clean up after a session ends.
sub done {
    my $sess = shift;
    $sess->fire('done');
    $sess->om->remove_session($sess) if $sess->om;
    exists $sess->{$_} && delete $sess->{$_} foreach qw(
        running waiting connected omegle_id typing im_typing
        typing_1 typing_2 type challenge waiting_for_captcha
        message_id_counter
    );
}

# parse events from Omegle.
sub handle_events {
    my ($sess, $data) = @_;
    my $om = $sess->om;

    # must be an array of events for us to care.
    return if index($data, '[');

    # event JSON
    $sess->fire(debug_raw => $data);
    my $events = $sess->decode($data);
    $sess->handle_event($om, @$_) foreach @$events;

    # request more events.
    $sess->request_next_event if $sess->id;
}

# request an event from Omegle.
sub request_next_event {
    my $sess = shift;
    $sess->debug('Requesting next event');
    $sess->post('events', [], \&handle_events, $sess);
}

# handle an event from Omegle.
sub handle_event {
    my ($sess, $om, $event_name, @event) = @_;

    # fire debug events.
    my $stuff = join ', ', @event;
    $sess->debug("EVENT: $event_name($stuff)");
    $sess->fire("raw_$event_name" => @event);

    # do we handle this?
    my $code = $sess->can("e_$event_name");
    if (!$code) {
        $sess->debug("Unknown event: $event_name");
        return
    }

    $code->($sess, $om, @event);
}

# status info update.
sub e_statusInfo {
    my ($sess, $om, $status_info) = @_;
    $om->_update_status($status_info);
    # status_update called later.
}

# message from server.
sub e_serverMessage {
    my ($sess, $om, $message) = @_;
    $sess->fire(server_message => $message);
}

# waiting on a chatting partner.
sub e_waiting {
    my ($sess, $om) = @_;
    $sess->{waiting} = 1;
    $sess->fire('waiting');
}

# session established.
sub e_connected {
    my ($sess, $om) = @_;
    delete $sess->{waiting_for_captcha};
    $sess->{connected} = 1;
    delete $sess->{waiting};
    $sess->fire('connected');
}

# stranger said something.
sub e_gotMessage {
    my ($sess, $om, $message) = @_;
    $sess->fire(message => $message);
    delete $sess->{typing};
}

# stranger disconnected.
sub e_strangerDisconnected {
    my ($sess, $om) = @_;
    $sess->fire('disconnected');
    $sess->done;
}

# stranger is typing.
sub e_typing {
    my ($sess, $om) = @_;
    continue if $sess->opt('no_type');
    $sess->fire('typing') unless $sess->{typing};
}

# stranger stopped typing.
sub e_stoppedTyping {
    my ($sess, $om) = @_;
    continue if $sess->opt('no_type');
    $sess->fire('stopped_typing') if $sess->{typing};
    delete $sess->{typing};
}

# stranger has similar interests.
sub e_commonLikes {
    my ($sess, $om, $interests) = @_;
    return if !ref $interests || ref $interests ne 'ARRAY';
    $sess->fire(common_interests => @$interests);
}

# question is asked.
sub e_question {
    my ($sess, $om, $question) = @_;
    $sess->fire(question => $question);
}

# spyee disconnected.
sub e_spyDisconnected {
    my ($sess, $om, $which) = @_;
    $which =~ s/Stranger //;
    $sess->fire(spy_disconnected => $which);
    $sess->done;
}

# spyee is typing.
sub e_spyTyping {
    my ($sess, $om, $which) = @_;
    continue if $sess->opt('no_type');
    $which =~ s/Stranger //;
    $sess->fire(spy_typing => $which) unless $sess->{"typing_$which"};
    $sess->{"typing_$which"} = 1;
}

# spyee stopped typing.
sub e_spyStoppedTyping {
    my ($sess, $om, $which) = @_;
    continue if $sess->opt('no_type');
    $which =~ s/Stranger //;
    $sess->fire(spy_stopped_typing => $which) if $sess->{"typing_$which"};
    delete $sess->{"typing_$which"};
}

# spyee said something.
sub e_spyMessage {
    my ($sess, $om, $which, $message) = @_;
    $which =~ s/Stranger //;
    $sess->fire(spy_message => $which, $message);
    delete $sess->{"typing_$which"};
}

# number of people online.
# this event is mostly obsolete due to statusInfo.
# however, Omegle appears to still send it under certain circumstances.
# for that reason, we will continue to handle it.
sub e_count {
    my ($sess, $om, $count) = @_;
    $om->{online} = $count;

    # we fire this on the Omegle instance.
    $om->fire(update_user_count => $count);
}

# an error has occured, and the session must end.
sub e_error {
    my ($sess, $om, $error) = @_;
    $sess->fire(error => $error);
    $sess->done;
}

# captcha was rejected.
sub e_recaptchaRejected {
    my ($sess, $om) = @_;
    $sess->fire('bad_captcha');
    &e_recaptchaRequired;
}

# server requests captcha.
sub e_recaptchaRequired {
    my ($sess, $om, $key) = @_;
    $sess->{waiting_for_captcha} = 1;
    $sess->fire(captcha_required => $key);

    # ask reCAPTCHA for an image.
    $om->get($CAPTCHA_CHLNG.$key, sub {
        my $data = shift;

        # ???
        if ($data !~ m/challenge : '(.+)'/) {
            $sess->debug("Couldn't find captcha challenge");
            return;
        }

        # got it; fire the callback.
        $sess->{challenge} = $1;
        $sess->fire(captcha => $CAPTCHA_IMAGE.$1);
    });
}

# post to the session server with the 'id' variable.
sub post {
    my ($sess, $page, $vars, $callback, @args) = @_;
    my $om = $sess->om or return;
    $om->post("http://$$sess{server}/$page", [
        id => $sess->id,
        @{ $vars || [] }
    ], $callback, @args);
}

# fire an event.
# this fires the event on the session object.
# it also fires the event on the Omegle object, using the session as the first argument.
sub fire {
    my ($sess, $event_name, @args) = @_;
    my @events = [ $event_name => @args ];
    push @events, [ $sess->om, $event_name => $sess, @args ] if $sess->om;
    $sess->fire_events_together(@events);
    return 1;
}

# get an option, either from the session or from the Omegle instance.
sub opt {
    my ($sess, $opt) = @_;
    return $sess->{$opt} || ($sess->om ? $sess->om->{opts}{$opt} : undef);
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

# returns the omegle manager.
sub om {
    return shift->{om};
}

# returns whether the server is waiting on a captcha response.
sub waiting_for_captcha {
    return shift->{waiting_for_captcha};
}

# encode/decode JSON.
sub encode;
sub decode;
*encode = *Net::Async::Omegle::encode;
*decode = *Net::Async::Omegle::decode;

# returns true if the stranger is typing.
# in ask/answer modes, returns true if either stranger is typing.
sub stranger_typing {
    my ($sess, $num) = @_;
    return unless $sess->{connected};
    if (defined $num) {
        return $sess->{"typing_$num"};
    }
    return $sess->{typing} || $sess->{typing_1} || $sess->{typing_2} || undef;
}

# returns the server this session is taking place on.
sub server {
    return shift->{server};
}

# returns the session type.
sub session_type {
    return shift->opt('type');
}

sub debug;
*debug = *Net::Async::Omegle::debug;

1
