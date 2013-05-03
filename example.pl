# Copyright (c) 2013, Mitchell Cooper

use Net::Async::Omegle;

use warnings;
use strict;
use feature 'say';

# create an Omegle manager instance.
my $om = Net::Async::Omegle->new;

# create an IO::Async::Loop and add the Omegle manager instance.
my $loop = IO::Async::Loop->new;
$loop->add($om);
$om->init;

# create a session.
my $sess = $om->new();

$sess->on(debug => sub { say "@_" });


# send messages back to the user after 5 seconds.
$sess->on(message => sub {
    my ($event, $msg) = @_;
    my $timer = IO::Async::Timer::Countdown->new(
        delay     => 5,
        on_expire => sub {
            say "You: $msg";
            $sess->say($msg);
        }
    );
    $timer->start;
    $loop->add($timer);
});

# start it when Omegle is ready.
$om->on(ready => sub {
    say 'Ready to connect.';
    $sess->start;
});


# run the loop.
$loop->run;
