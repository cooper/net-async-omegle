########################################
  package  Net::Async::Omegle          #
# ------------------------------------ #
# A clean, non-blocking Perl interface #
# to Omegle.com for the IO::Async.     #
# http://github.com/cooper/new-omegle  #
#             ...and net-async-omegle. #
########################################
;
# Copyright (c) 2011-2012, Mitchell Cooper

use warnings;
use strict;
use base 'IO::Async::Notifier';
use 5.010;

use IO::Async::Timer::Periodic;
use Net::Async::HTTP;
use Net::Async::Omegle::Session;
use JSON ();
use URI  ();

our $VERSION = 3.9;
our $ua = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/535.11 (KHTML, like Gecko)
Chrome/17.0.963.12 Safari/535.11"; $ua =~ s/\n/ /g;

sub new {
    my $ref = shift;

    # create a new Omegle session object.
    if (ref $ref) {
        my $sess = Net::Async::Omegle::Session->new(@_);
        $ref->add_session($sess);
        return $sess;
    }

    # create a new Omegle instance (IO::Async::Notifier).
    $ref->SUPER::new(@_);
}

# IO::Async::Notifier configure.
sub configure {
    my ($om, %params) = @_;

    foreach (qw|
        on_debug on_got_id on_connect on_disconnect on_error on_chat on_type on_stoptype
        on_commonlikes on_question on_spydisconnect on_spytype on_spystoptype on_spychat
        on_wantcaptcha on_gotcaptcha on_badcaptcha use_likes use_question want_question
        topics question server static no_type
    |) {
        $om->{opts}{$_} = delete $params{$_} if exists $params{$_};
    }

    $om->SUPER::configure(%params);
}

# new instance created.
sub _init {
    my $om = shift;

    # create HTTP instance
    my $http = $om->{http} = Net::Async::HTTP->new(user_agent => $ua);
    $om->add_child($http);

    # create status update timer
    my $timer = $om->{timer} = IO::Async::Timer::Periodic->new(
        interval => 300,
        on_tick  => sub { $om->status_update() }
    );
    $om->add_child($timer);
}

# should be called right after $loop->add().
sub init {

    # initial status update
    shift->status_update();
}

# returns the index of the next server in line to be used
sub newserver {
    my $om = shift;
    $om->{servers}[
        $om->{lastserver} == $#{$om->{servers}} ? $om->{lastserver} = 0
        : ++$om->{lastserver}
    ]
}

# make a POST request.
sub post {
    my ($om, $uri, $vars, $callback, @args) = @_;

    $om->{http}->do_request(
        method       => 'POST',
        uri          => URI->new($uri),
        content      => $vars || [],
        on_error     => sub { },
        on_header => sub { sub {
            my $content = shift || return;
            $callback->(@args, $content) if $callback;
        } }
    ) or return;

    return 1;
}

# make a GET request.
sub get {
    my ($om, $uri, $callback, @args) = @_;

    $om->{http}->do_request(
        method       => 'GET',
        uri          => URI->new($uri),
        on_error     => sub { },
        on_response  => sub { $callback->(@args, shift->content) if $callback }
    ) or return;

    return 1;
}

# update server status and user count.
sub status_update {
    my $om = shift;

    $om->post('http://omegle.com/status', [], sub {
        my $data          = JSON::decode_json(shift);
        $om->{servers}    = $data->{servers};
        $om->{lastserver} = $#{$data->{servers}};
        $om->{online}     = $data->{count};
        $om->{updated}    = time;
    });
}

# add a session to this omegle instance.
sub add_session {
    my ($om, $sess) = @_;
    return if $sess->{om} && $sess->{om} == $om;
    $om->{sessions}{$sess->{omegle_id}} = $sess if $sess->{omegle_id};
    $sess->{om} = $om;
    return 1;
}

# remove a session from this omegle instance.
sub remove_session {
    my ($om, $sess) = @_;
    return if !$sess->{om} || $sess->{om} != $om;
    delete $om->{sessions}{$sess->{omegle_id}};
    delete $sess->{om};
    return 1;
}

1
