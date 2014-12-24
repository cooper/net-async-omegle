package Net::Async::HTTP::MultiConn;

# the purpos

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