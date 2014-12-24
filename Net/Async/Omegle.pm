###############################################
  package     Net::Async::Omegle              ;
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
use parent qw(IO::Async::Notifier Evented::Object); # notifier must be first for SUPER.
use 5.010;

use Evented::Object;

use IO::Async::Timer::Periodic;
use Net::Async::HTTP::MultiConn;
use Net::Async::Omegle::Session;
use JSON ();
use URI  ();

our $VERSION = '5.23';

# default user agent. used only if 'ua' option is not provided to the Omegle instance.
our $ua = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/535.11 (KHTML, like Gecko)
Chrome/17.0.963.12 Safari/535.11";

sub new {
    my $ref = shift;

    # create a new Omegle session object.
    if (ref $ref) {
        my $sess = Net::Async::Omegle::Session->new(@_);
        $ref->add_session($sess);
        return $sess;
    }

    # create a new Omegle instance (IO::Async::Notifier).
    return $ref->SUPER::new(@_);
    
}

# IO::Async::Notifier configure.
sub configure {
    my ($om, %params) = @_;

    $params{type} ||= 'Traditional';

    foreach (qw|topics question server static no_type type|) {
        $om->{opts}{$_} = delete $params{$_} if exists $params{$_};
    }

    $om->SUPER::configure(%params);
}

# new instance created.
sub _init {
    my $om = shift;
    $om->{init} = 1;
    
    # create HTTP instance
    $ua =~ s/\n/ /g;
    my $http = $om->{http} = Net::Async::HTTP::MultiConn->new(
        user_agent => $om->{ua} || $ua
    );
    $om->add_child($http);

    # create status update timer
    my $timer = $om->{timer} = IO::Async::Timer::Periodic->new(
        interval => 300,
        on_tick  => sub {
            return unless time - ($om->{updated} || 0) >= 300;
            $om->status_update();
        }
    );
    $om->add_child($timer);
    $om->status_update if $om->loop;
}

# update after being added to loop.
sub _add_to_loop {
    my ($om, $loop) = @_;
    $om->_init if !$om->{init};
    $om->status_update;
}

# returns the index of the next server in line to be used
sub newserver {
    my $om = shift;
    $om->{servers}[
        (defined $om->{lastserver} && $om->{lastserver} == $#{$om->{servers}}) ? $om->{lastserver} = 0
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

# compat.
sub init   { &status_update }
sub update { &status_update }

# update server status and user count.
sub status_update {
    my $om = shift;

    $om->post('http://omegle.com/status', [], sub {
        my $data = JSON::decode_json(shift);
        $om->_update_status($data);
    });
}

# handle a status update.
sub _update_status {
    my ($om, $data) = @_;
    $om->{servers}    = $data->{servers};
    $om->{lastserver} = $#{$data->{servers}};
    $om->{online}     = $data->{count};
    $om->{toosexy}    = $data->{force_unmon};
    $om->{updated}    = time;
    
    # fire the generic status update event.
    $om->fire('status_update');
    $om->fire(update_user_count => $data->{count});
    
    # fire ready event if we haven't already.
    if (!$om->{fired_ready}) {
        $om->fire('ready');
        $om->{fired_ready} = 1;
    }
    
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

# returns the number of users currently online.
sub user_count {
    my $om = shift;
    return my @a = ($om->{online} || 0, $om->{updated}) if wantarray; 
    return $om->{online} || 0;
}

# returns whether the user has been forced into the unmonitored section.
sub half_banned { shift->{toosexy} }

# returns an array of available servers.
sub servers {
    my $om = shift;
    return @{$om->{servers}} if $om->{servers};
    return my @a;
}

# returns the name of the last server used.
sub last_server {
    my $om = shift;
    return if !defined $om->{lastserver};
    return $om->{servers}[$om->{lastserver}];
}

1
