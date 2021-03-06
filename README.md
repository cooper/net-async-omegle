# Net::Async::Omegle

This is a Perl interface to the Omegle.com anonymous chatting service. It is
designed for use with the IO::Async event framework. Net::Async::Omegle supports
all Omegle events, allowing your program to respond to messages, typing, stopped
typing, connects, disconnects, and more. Using IO::Async and Net::Async::HTTP,
it is completely non-blocking and can be placed easily in many programs.
Recently, support has been added for Omegle's reCAPTCHA API and many other new
features such as the common interests system, spying sessions, and question
(spy) modes.  

As of version 4.2, Net::Async::Omegle depends on Evented::Object, located at http://github.com/cooper/evented-object.  
Evented::Object is also available on
[CPAN](http://search.cpan.org/perldoc?Evented::Object).

## Author

Mitchell Cooper, <mitchell@notroll.net>  
Feel free to contact me via github's messaging system if you have a question or
request.   You are free to modify and redistribute Net::Async::Omegle under the
terms of the New BSD license. See LICENSE.

## Options

These options can be either manager-specific or session-specific. Any options
passed to `$om->new()` (the session constructor) will override those passed
to `Net::Async::Omegle->new()` (the manager constructor).

- __type__ - type of session ('Traditional', 'CommonInterests', 'AskQuestion',
  or 'AnswerQuestion') - defaults to Traditional.
- __server__ - specify a server. this typically is a bad idea since NaOmegle
  supports Omegle's automatic load balancing.
- __topics__ - array reference of your interests
  (required if type = 'CommonInterests').
- __question__ - a question for two strangers to discuss
  (required if type = 'AskQuestion').
- __static__ - if true, do not cycle through the server list. this is probably
  a bad idea.
- __no_type__ - true if you think typing events are annoying and useless.
- __ua__ - HTTP user agent string. defaults to $Net::Async::Omegle::ua.
 to 'Traditional'
- __mobile__ - true if you wish to identify as connecting from a mobile device.

## Events

Net::Async::Omegle uses the Evented::Object framework for events. Most events
are fired on session objects; however, all events fired on session objects are
also fired on Omegle manager objects with the session object as the first
argument. Programatically, you have the choice between using a single handler
for all sessions or using callbacks specific to certain sessions.  

Both of these are valid for handling message events, for example.
```perl
# This callback is specific to this session.
$sess->on(stranger_message => sub {
    my ($event, $message) = @_;
    say "Stranger said: $message";
});
```
```perl
# This applies to all sessions in this Omegle manager instance.
$om->on(stranger_message => sub {
    my ($event, $sess, $message) = @_;
    say "Stranger said: $message";
    # notice that the session is the first event argument.
});
```

### omegle.ready()

Fired when the first Omegle status update completes. You must wait for this
event to be called before starting any conversations. This ensures that the
available Omegle servers have been fetched in advance.

```perl
my $sess = $om->new();
$om->on(ready => sub {
    $sess->start();
});
```

### omegle.update_user_count($user_count)

Fired when the user count is updated.  
Note: this is fired immediately after `status_update`, but it is more reliable
for user count because the user count may also be updated by an Omegle
conversation event.

```perl
$om->on(update_user_count => sub {
    my ($event, $count) = @_;
    say "There are now $count users online.";
});
```

* __$user_count__ - the new global user count on Omegle.com.

### omegle.status_update()

Fired when the Omegle status information is updated. This is fired quite
frequently. This status information sets the Omegle server list, user count, and
several other pieces of data.

```perl
$om->on(status_update => sub {
    my @servers = $om->servers;
    say "Available servers: @servers\n";
});
```

Note: this should not be used for user count updates as `update_user_count` is
more reliable.

### session.start()

Fired when the session is started. At this point, a stranger has not been found.
This merely indicates that the start request has been submitted. After this is
fired, `$sess->running` will return true until the session ends.

```perl
$sess->on(start => sub { say 'Session '.$sess->id.' started.' });
```

The order of events after calling `->start()` is typically:
1. `start`
2. `got_id`
3. `waiting`
4. `connected`

### session.got_id($id)

Fired when the Omegle session identifier is received. After this is fired,
`$sess->id` will contain the session identifier until the session terminates.

```perl
$sess->on(got_id => sub {
    my ($event, $id) = @_;
    say 'My ID is: '.$id;
});
```

### session.waiting()

Fired when the session is waiting for a chatting partner to connect. This is
fired after `start` and before `connected`. After this is fired,
`$sess->waiting` will return true until a stranger is found.

```perl
$sess->on(waiting => sub { say 'Waiting on a stranger...' });
```

### session.connected()

Fired when a stranger is found and a conversation begins. After this is fired,
`$sess->connected` will return true until the conversation ends.

```perl
$sess->on(connected => sub { $sess->say('Hi there, Stranger!') });
```

### session.common_interests(@interests)

```perl
$sess->on(common_interests => sub {
    my ($event, @interests) = @_;
    say "You and the stranger have in common: @interests";
});
```

* __@interests__ - the list of interests which you and stranger have in common.

### session.question($question)

Fired when the question is received in ask and answer modes. This is fired even
if you are the one asking the question.

```perl
$session->on(question => sub {
    my ($event, $question) = @_;
    say "Question up for discussion: $question";
});
```

* __$question__ - the question text up for discussion.

### session.server_message($message)

Fired when the server notifies you with a piece of text information. This
typically is used to let you know that the stranger is using a mobile device or
other special software. However, it may have other uses in the future.

```perl
$sess->on(server_message => sub {
    my ($event, $msg) = @_;
    say "Server: $msg";
});
```

* __$message__ - the message text from the Omegle server.

### session.typing()

Fired when the stranger begins typing. After being fired,
`$sess->stranger_typing` becomes true.

```perl
$sess->on(typing => sub {
    say 'Stranger is typing...';
});
```

### session.stopped_typing()

Fired when the stranger stops typing. After being fired,
`$sess->stranger_typing` becomes false.

```perl
$sess->on(stop_typing => sub {
    say 'Stranger is typing...';
});
```

Note: this event is not fired when a stranger sends a message (which also
terminates typing.)

### session.message($message)

Fired when the stranger sends a message. After being fired,
`$sess->stranger_typing` resets to a false value.

```perl
$sess->on(message => sub {
    my ($event, $msg) = @_;
    say "Stranger: $message";
});
```

* __$message__ - the message text from the stranger.

### session.you_message($message, $id)

Fired when your message is delivered.

* __$message__ - the message text as you sent it.
* __$id__ - the message ID, which was previously returned by `->say()`.

### session.disconnected()

Fired when the stranger disconnects from the conversation. This ends the
session, resetting all of its values to their defaults.

```perl
$sess->on(disconnected => sub {
    say 'Your conversational partner has disconnected.';
});
```

### session.spy_typing($which)

Fired when a stranger in ask/answer mode begins typing. After being fired,
`$sess->stranger_typing($which)` becomes true.

```perl
$sess->on(spy_typing => sub {
    my ($event, $which) = @_;
    say "Stranger $which is typing...";
});
```

* __$which__ - the identifier of the stranger which disconnected (`1` or `2`).

### session.spy_stopped_typing($which)

Fired when a stranger in ask/answer mode stops typing. After being fired,
`$sess->stranger_typing($which)` becomes false.

```perl
$sess->on(spy_stop_typing => sub {
    my ($event, $which) = @_;
    say 'Stranger $which is typing...';
});
```

Note: this event is not fired when a stranger sends a message (which also
terminates typing.)

* __$which__ - the identifier of the stranger which disconnected (`1` or `2`).

### session.spy_message($which, $message)

Fired when a stranger in ask/answer mode sends a message. After being fired,
`$sess->stranger_typing($which)` resets to a false value.

```perl
$sess->on(spy_message => sub {
    my ($event, $which, $msg) = @_;
    say "Stranger $which: $message";
});
```

* __$which__ - the identifier of the stranger which disconnected (`1` or `2`).
* __$message__ - the message text from the stranger.

### session.spy_disconnected($which)

Fired when a stranger in ask/answer mode disconnects from the conversation.
This ends the session, resetting all of its values to their defaults.

```perl
$sess->on(spy_disconnected => sub {
    my $which = shift;
    say "Your conversational partner #$which has disconnected.";
});
```

* __$which__ - the identifier of the stranger which disconnected (`1` or `2`).

### session.captcha_required($challenge)

Fired when the server requests that a captcha be submitted. Net::Async::Omegle
will automatically request a captcha and fire `captcha` afterwards.

```perl
$sess->on(captcha_required => sub { say 'Fetching captcha...' });
```

* __$challenge__ - the captcha challenge key.


### session.captcha($url)

Fired when a captcha image address is fetched.

```perl
$sess->on(captcha => sub {
    my ($event, $url) = @_;
    say "Please verify that you are human: $url";
});
```

* __$url__ - the absolute URL of the captcha image challenge.

### session.bad_captcha()

Fired when a captcha submission is denied. Net::Async::Omegle will automatically
request a new captcha.

```perl
$sess->on(bad_captcha => sub { say 'Incorrect captcha. Fetching another...' });
```

### session.done()

Fired when the session is complete. This could be due to an error, you
disconnecting, or a stranger disconnecting. It is fired after the event which
caused it (disconnected, etc.) and  before deleting the values associated with
the session, allowing you to do any final cleanups.

```perl
$sess->on(done => sub { delete $sessions{$sess} });
```

### session.error($message)

Fired when the server returns an error. This ends the session, resetting all of
its values to their defaults.

```perl
$sess->on(error => sub {
    my ($event, $message) = @_;
    say "Omegle error: $message";
});
```

* __$message__ - the error message text from the Omegle server.

### session.raw_*(@arguments)

raw_* events are fired for each raw Omegle event. Typically, you do not want to
handle these directly and should use the several other convenient events
provided.

* __@arguments__ - the list of raw event parameters sent by the Omegle server.

### session.debug($message)

Log events are fired for debugging purposes.

* __$message__ - a string of debug info.

## Omegle manager methods

### $om = Net::Async::Omegle->new(%options)

Creates an Omegle manager object. After creating it, you should `->add` it to
your IO::Async::Loop. Once it has been added, you should `$om->init` it. Any of
the options listed above may be used, but all are optional.

```
my $om = Net::Async::Omegle->new(%opts);
```

See the list of [available options](#options).

### $om->user_count

Returns the number of users currently online.  
In list context, the time at which this information was last updated is
also returned.

```perl

# just the user count
my $count = $om->user_count;

# or if you need the update time
my ($user_count, $update_time) = $om->user_count;

say "$user_count users online as of ", scalar localtime $update_time;
```

### $om->half_banned

Returns whether your client has been forced into unmonitored mode.
This occurs when your behavior is too sexual.

### $om->update

Updates Omegle status information. This must be called initially after adding
the Omegle object to the loop. After the first status information request
completes, the `ready` event will be fired. From there on, it is safe to call
`->start()` on a session instance. This event will only be fired once.

```perl
my $sess = $om->new;
$om->update;
$om->on(ready => sub {
    say 'Status information received; starting conversation.';
    $sess->start();
});
```

### $om->servers

Returns an array of available Omegle servers.

```perl
my @servers = $om->servers;
```

### $om->last_server

Returns the name of the last server used (or the current one while a session is
running.)

```perl
my $server = $om->last_server;
```

## Omegle session methods

Session methods are safe for asynchronous callbacks. For example, if you have a
timer which sends a message after 5 seconds but the stranger disconnects during
that time, calling `->say()` is harmless and will do nothing.

### $sess = $om->new(%options)

Creates a new Net::Async::Omegle::Session object. This object represents a
single Omegle session. Any of the options listed above may be used, but all are
optional.

```
my $sess = $om->new(%opts);
```

See the list of [available options](#options).

### $sess->start

Starts the Omegle session. This method immediately returns true no matter what.
In order to handle the success/failure of it, you must hook onto events.

Note: you should not call this method until you know the Omegle manager is
ready. The `ready` event will be fired on the Omegle manager when this is the
case.

```perl
$om->on(ready => sub { $sess->start });
```

### $sess->type

Makes it appear that you are typing.
Returns true or `undef` if there is no session connected.

```perl
$sess->type;
```

### $sess->stop_typing

Makes it appear that you have stopped typing.
Returns true or `undef` if there is no session connected.

```perl
$sess->stop_typing;
```

### $id = $sess->say($message)

Sends a message to the stranger.

Returns `undef` if there is no session connected. Otherwise, returns a message
ID which may later be passed to the `you_message` event upon delivery.

```perl
my $id = $sess->say('hey there :]');
```

* __$message__ - the text to send to the stranger.

### $sess->disconnect

Disconnects from the current session.
Returns true or `undef` if there is no session connected.
You can immediately start a new session on the same object with `$sess->start()`.

```perl
$sess->disconnect;
```

### $sess->submit_captcha($answer)

Submits a response to recaptcha. If incorrect, a new captcha will be presented
and the `on_badcaptcha` event will be fired.

```perl
$sess->submit_captcha('some CAPTCHA');
```

* __$answer__ - the user-determined captcha response.

### $sess->running

Returns true if the session is currently running. This does not necessarily mean
that a conversation is in progress; it merely indicates that a request has been
submit to start a new conversation. After the session terminates, this method
returns false.

```perl
say 'A session is in progress' if $sess->running;
```

### $sess->waiting

Returns true if the session is waiting on a stranger to be paired with. Once a
stranger is found, this method will return false.

```perl
say 'Losing my patience...' if $sess->waiting;
```

### $sess->connected

Returns true if a session is running and a conversation is in progress. This
means that a stranger has been found. After the session terminates, this method
returns false.

```perl
say 'Chatting with someone...' if $sess->connected;
```

### $sess->id

Returns the Omegle session identifier or `undef` if it has not yet been
received. Note: the session identifier can also be obtained when it is received
with the `got_id` event.

```perl
$sess->on(connect => sub {
    say 'Conversation (ID: '.$sess->id.') started.';
});
```

### $sess->stranger_typing($stranger_num)

Returns true if the stranger is currently typing. In a mode with multiple
strangers, this method returns true if either of the two strangers are typing.
Optionally, you may suppy `1` or `2` for the typing status of a specific
stranger in ask and answer modes.

```perl
$sess->on(type => sub {
    my $timer = IO::Async::Timer::Countdown->new(
        delay     => 10,
        on_expire => sub {
            say 'This guy types slow.' if $sess->stranger_typing;
        }
    );
    $timer->start;
    $loop->add($timer);
}));
```

* __$stranger_num__ - _optional_, which stranger you are checking, if the
session is in ask or answer mode.

### $sess->server

Returns the name of the server the session is taking place on.

```perl
$sess->on(connect => sub { say 'Found stranger on '.$sess->server });
```

### $sess->session_type

Returns the session type.

* __Traditional__ - one-on-one chat with no special features.
* __CommonInterests__ - one-on-one chat with chat topics enabled.
* __AskQuestion__ - spy mode where you are asking the question.
* __AnswerQuestion__ - spy mode where you are answering the question.

```perl
if ($sess->session_type eq 'AskQuestion') {
    $sess->{question} = 'What time is it in Paris?';
}
```

### $sess->waiting_for_captcha

Returns true if the server is waiting on a captcha response.

```perl
if ($sess->waiting_for_captcha) {
    say 'Already sent captcha response';
}
else {
    $sess->submit_captcha('homeboy 2378');
}
```
