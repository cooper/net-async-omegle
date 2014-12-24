package Net::Async::HTTP::MultiConn;
#
# Net::Async::HTTP queues connections to a certain
# host and port. This behavior does not work with
# Omegle because the service hangs until events are
# received. Therefore, if you send a message, it would
# not actually be sent until an event was received
# from the stranger. This wrapper prevents that by
# always returning a new connection object.
#
use warnings;
use strict;
use 5.010;

use parent 'Net::Async::HTTP';

sub get_connection {
    my ($self, @args) = @_;
    $self->{connections} = {};
    return $self->SUPER::get_connection(@args);
}

1