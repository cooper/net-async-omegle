# Net::Async::Omegle

This is a Perl interface to the Omegle.com anonymous chatting service. It is designed for use with the IO::Async event framework. Net::Async::Omegle supports all Omegle events, allowing your program to respond to messages,
typing, stopped typing, connects, disconnects, and more. Using IO::Async and Net::Async::HTTP, it is completely non-blocking and can
be placed easily in many programs. Recently, support has been added for Omegle's reCAPTCHA API and many other new features such as the
common interests system, spying sessions, and question (spy) modes.  
  
As of version 4.2, Net::Async::Omegle depends on EventedObject, located at http://github.com/cooper/evented-object.

## Author

Mitchell Cooper, <mitchell@notroll.net>  
Feel free to contact me via github's messaging system if you have a question or request.  
You are free to modify and redistribute Net::Async::Omegle under the terms of the New BSD license. See LICENSE.

## Options

If you specify options to `$om->new()` (the session constructor), those options will always
override the ones that you specified to `Net::Async::Omegle->new()`. In other words, All options are optional, but not specifying any is quite useless.
Callbacks (prefixed with on) must be CODE references. What is in parenthesis will be passed when called. However, the session
object will always be the first argument of all callbacks.

- __type__: type of session ('Traditional', 'CommonInterests', 'AskQuestion', or 'AnswerQuestion') - defaults
- __server__: specify a server (don't do this.)
- __topics__: array reference of your interests (if type = CommonInterests)
- __question__: a question for two strangers to discuss (if type = AskQuestion)
- __static__: if true, do not cycle through server list (don't do this.)
- __no_type__: true if you think typing events are annoying and useless
- __ua__: HTTP user agent string. defaults to $Net::Async::Omegle::ua (not session-specific)
 to 'Traditional'
- __mobile__: true if you wish to identify as connecting from a mobile device

## Events

Net::Async::Omegle uses the EventedObject framework for events. Most events are fired on
session objects; however, all events fired on session object are also fired on Omegle
manager objects with the session object as the first argument. Programatically, you have
the choice between using a single handler for all sessions or using callbacks specific
to certain sessions.  

For example, both of these are valid for handling message events.
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

Fired when the first Omegle status update completes. You must wait for this event to be
called before starting any conversations. This ensures that the available Omegle servers
have been fetched in advance.

```perl
my $sess = $om->new();
$om->on(ready => sub {
    $sess->start();
});
```

### omegle.update_user_count($user_count)

Fired when the user count is updated.  
Note: this is fired immediately after `status_update`, but it is more reliable for user
count because the user count may also be updated by an Omegle conversation event.

```perl
$om->on(update_user_count => sub {
    my ($event, $count) = @_;
    say "There are now $count users online.";
});
```

### session.start()

Fired when the session is started. At this point, a stranger has not been found. This
merely indicates that the start request has been submitted. After this is fired,
`$sess->running()` will return true until the session ends.

```perl
$sess->on(start => sub { say 'Session '.$sess->id.' started.' });
```

Note: the order of events after calling `->start()` is typically `start`, `got_id`, `waiting`, `connected`.

### session.got_id($id)

Fired when the Omegle session identifier is received. After this is fired, `$sess->id`
will contain the session identifier until the session terminates.

```perl
$sess->on(got_id => sub {
    my ($event, $id) = @_;
    say 'My ID is: '.$id;
});
```

Note: the order of events after calling `->start()` is typically `start`, `got_id`, `waiting`, `connected`.

### session.waiting()

Fired when the session is waiting for a chatting partner to connect. This is fired
after `start` and before `connected`. After this is fired, `$sess->waiting()` will return
true until a stranger is found.

```perl
$sess->on(waiting => sub { say 'Waiting on a stranger...' });
```

Note: the order of events after calling `->start()` is typically `start`, `got_id`, `waiting`, `connected`.

### session.connected()

Fired when a stranger is found and a conversation begins. After this is fired, `$sess->connected()`
will return true until the conversation ends.

```perl
$sess->on(connected => sub { $sess->say('Hi there, Stranger!') });
```

Note: the order of events after calling `->start()` is typically `start`, `got_id`, `waiting`, `connected`.

### session.server_message($message)

Fired when the server notifies you with a piece of text information. This typically is used
to let you know that the stranger is using a mobile device or other special software. However,
it may have other uses in the future.

```perl
$sess->on(server_message => sub {
    my ($event, $msg) = @_;
    say "Server says: $msg";
});
```

## Omegle manager methods

### $om = Net::Async::Omegle->new(%options)

Creates an Omegle object. After creating it, you should `->add` it to your IO::Async::Loop. Once it has been added, you should
`$om->init` it. Any of the options listed above may be used, but all are optional.

```perl
my $om = Net::Async::Omegle->new(
    on_error         => \&error_cb,
    on_chat          => \&chat_cb,
    on_type          => \&type_cb,
    on_stoptype      => \&stoptype_cb,
    on_disconnect    => \&disconnect_cb,
    on_connect       => \&connect_cb,
    on_got_id        => \&got_id_cb,
    on_commonlikes   => \&commonlikes_cb,
    on_question      => \&question_cb,
    on_spydisconnect => \&spydisconnect_cb,
    on_spytype       => \&spytype_cb,
    on_spystoptype   => \&spystoptype_cb,
    on_spychat       => \&spychat_cb,
    on_wantcaptcha   => \&gotcaptcha_cb,
    on_gotcaptcha    => \&gotcaptcha_cb,
    on_badcaptcha    => \&badcaptcha_cb,
    server           => 'bajor.omegle.com',  # don't use this option without reason
    static           => 1,                   # or this one
    topics           => ['IRC', 'Omegle', 'ponies'],
    use_likes        => 1,
    use_question     => 1,
    no_type          => 1
);
```

### $om->user_count()

Returns the number of users currently online.  
Optionally returns the time at which this information was last updated.

```perl
my $count = $om->user_count;
my ($user_count, $update_time) = $om->user_count;

say "$user_count users online as of ", scalar localtime time;
```

### $om->update()

Updates Omegle status information. This must be called initially after adding the Omegle
object to the loop. After the first status information request completes, the `ready`
event will be fired. From there on, it is safe to call `->start()` on a session instance.  
This event will only be fired once.

```perl
my $sess = $om->new();
$om->update();
$om->on(ready => sub {
    say 'Status information received; starting conversation.';
    $sess->start();
});
```

### $om->servers()

Returns an array of available Omegle servers.

```perl
my @servers = $om->servers();
```

### $om->last_server()

Returns the name of the last server used (or the current one while a session is running.)

```perl
my $server = $om->last_server();
```

## Omegle session methods

### $sess = $om->new(%options)

Creates a new Net::Async::Omegle::Session object. This object represents a single Omegle session. Any of the options listed above
may be used, but all are optional.

```perl
my $sess = $om->new(
    server           => 'bajor.omegle.com',  # don't use this option
    static           => 1,                   # or this one
    topics           => ['IRC', 'Omegle', 'ponies'],
    use_likes        => 1,
    use_question     => 1,
    no_type          => 1
);
```

### $sess->start()

Connects to Omegle. This *does not* return the Omegle ID of your session as it does in New::Omegle. It returns true.
If you need the session ID for whatever reason, use the `on_got_id` event.  
Note: you should not call this method until you know the Omegle manager is ready.
The `ready` event will be fired on the Omegle manager when this is the case.

```perl
$sess->start();
```

### $sess->go()

Method does not exist. This functionality is now handled automatically.

### $sess->type()

Makes it appear that you are typing.
Returns true or `undef` if there is no session connected.

```perl
$sess->type();
```

### $sess->stoptype()

Makes it appear that you have stopped typing.
Returns true or `undef` if there is no session connected.

```perl
$sess->stoptype();
```

### $sess->say($message)

Sends a message to the stranger.
Returns true or `undef` if there is no session connected.

```perl
$sess->say('hey there :]');
```

### $sess->disconnect()

Disconnects from the current session.
Returns true or `undef` if there is no session connected.
You can immediately start a new session on the same object with `$sess->start()`.

```perl
$sess->disconnect();
```

### $sess->submit_captcha($answer)

Submits a response to recaptcha. If incorrect, a new captcha will be presented and the
`on_badcaptcha` event will be fired.

```perl
$sess->submit_captcha('some CAPTCHA');
```

### $sess->running()

Returns true if the session is currently running. This does not necessarily mean that
a conversation is in progress; it merely indicates that a request has been submit to
start a new conversation. After the session terminates, this method returns false.

```perl
say 'A session is in progress' if $sess->running();
```

### $sess->waiting()

Returns true if the session is waiting on a stranger to be paired with. Once a stranger is
found, this method will return false.

```perl
say 'Losing my patience...' if $sess->waiting();
```

### $sess->connected()

Returns true if a session is running and a conversation is in progress. This means that
a stranger has been found. After the session terminates, this method returns false.

```perl
say 'Chatting with someone...' if $sess->connected();
```

### $sess->id()

Returns the Omegle session identifier or `undef` if it has not yet been received.  
Note: the session identifier can be obtained when it is received with the `got_id` event.

```perl
$sess->on(connect => sub {
    say 'Conversation (ID: '.$sess->id.') started.';
});
```

### $sess->stranger_typing([$stranger_num])

Returns true if the stranger is currently typing. In a mode with multiple strangers,
this method returns true if either of the two strangers are typing. Optionally, you may
suppy `1` or `2` for the typing status of a specific stranger in ask and answer modes.

```perl
$sess->on(type => sub {
    my $timer = IO::Async::Timer::Countdown->new(
        delay     => 10,
        on_expire => sub { say 'This guy types slow.' if $sess->stranger_typing }
    );
    $timer->start;
    $loop->add($timer);
}));
```

### $sess->server()

Returns the name of the server the session is taking place on.

```perl
$sess->on(connect => sub { say 'Found stranger on '.$sess->server });
```

