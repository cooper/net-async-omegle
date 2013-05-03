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

## variables

Your instance of Net::Async::Omegle, while attached to an IO::Async::Loop, will fetch these variables
from Omegle every five minutes at the very least. During a session, this information is updated
almost constantly. You can force an update at any time by calling `$om->update()`.  

- __$sess->{connected}__: true if the session has actually been established.
- __$sess->{omegle_id}__: your Omegle client ID.
- __$sess->{typing}__: true if the stranger is typing.
- __$sess->{typing_1}__: true if Stranger 1 in spy mode is typing.
- __$sess->{typing_2}__: true if Stranger 2 in spy mode is typing.
- __$sess->{server}__: the Omegle server this session is connected to.
- __$sess->{challenge}__: if there is a pending captcha, this is the reCAPTCHA challenge ID.

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

### $sess->start()

Connects to Omegle. This *does not* return the Omegle ID of your session as it does in New::Omegle. It returns true.
If you need the session ID for whatever reason, use the `on_got_id` event.

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
