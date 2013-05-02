# Copyright (c) 2013, Mitchell Cooper

use Net::Async::Omegle;

use warnings;
use strict;
use feature 'say';

my $om = Net::Async::Omegle->new(

);

my $loop = IO::Async::Loop->new;
$loop->add($om);
$om->init();


my $sess = $om->new(
    on_connect => sub { say "Connected!" },
    on_got_id  => sub { say "Conversation ID: ".$_[1] },
    on_debug   => sub { say "@_" }
);

my $timer = IO::Async::Timer::Countdown->new(
    delay => 3,
    on_expire => sub { $sess->start() }
);
$timer->start();
$loop->add($timer);


$loop->run;
