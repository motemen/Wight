package Wight::Node;
use strict;
use warnings;
use Sub::Name;
use Class::Accessor::Lite (
    new => 1,
    ro  => [
        'wight',
        'page_id',
        'id',
    ]
);

our @METHODS = qw(
    click set text visible
);

foreach my $method (@METHODS) {
    my $code = sub {
        my ($self, @args) = @_;
        return $self->wight->call($method => $self->page_id, $self->id, @args);
    };
    no strict 'refs';
    *$method = subname $method, $code;
}

*is_visible = \&visible;

sub find_within {
    my ($self, $selector) = @_;
    my $class = ref $self;
    my $id = $self->wight->call(find_within => $self->page_id, $self->id, $selector) or return;
    return $class->new(%$self, id => $id);
}

1
