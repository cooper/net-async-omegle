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


# start it when Omegle is ready.
$om->on(ready => sub {
    say 'Ready to connect.';
    $sess->start;
});


# run the loop.
$loop->run;
