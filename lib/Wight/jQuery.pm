package Wight::jQuery;
use strict;
use warnings;
use overload
    '""'  => '__as_javascript_string',
    '&{}' => '__add_arguments',
    '.'   => '__chain_property',
    fallback => 1;
use JSON;
use Storable qw(dclone);
use Exporter::Lite;

our @EXPORT = qw(jQuery);

our $NAME = 'jQuery';
our $json = JSON->new->allow_nonref;

sub jQuery {
    return __PACKAGE__->__new(@_ ? [ $NAME, [ @_ ] ] : [ $NAME ]);
}

sub __new {
    my ($class, @chain) = @_;
    return bless \@chain, $class;
}

sub __as_javascript_string {
    my $self = shift;
    return join '.', map {
        my ($method, $args) = @$_;
        !$args ? $method : sprintf "$method(%s)", join ', ', map {
            if (ref $_ eq 'CODE') {
                my @args = $_->();
                my $func = pop @args;
                sprintf "function (%s) { $func }", join(', ', @args);
            } elsif (ref $_ eq 'SCALAR') {
                $$_;
            } else {
                $json->encode($_);
            }
        } @$args;
    } @$self;
}

sub __chain_property {
    my ($self, $prop) = @_;
    return $self->__chain([ $prop ]);
}

sub __chain {
    my ($self, $next) = @_;
    my $class = ref $self;
    return $class->__new(@$self, $next);
}

sub __add_arguments {
    my $self = shift;
    return sub {
        my @args = @_;
        if ($self->[-1]->[1]) {
            return $self->__chain([ '', \@args ]);
        } else {
            my $self = dclone $self;
            $self->[-1]->[1] = \@args;
            return $self;
        }
    };
}

sub AUTOLOAD {
    my $method = our $AUTOLOAD;
       $method =~ s/^(.+):://;
    if (ref $_[0]) {
        my $self = shift;
        return $self->__chain([ $method, \@_ ]);
    } else {
        return __PACKAGE__->__new([ $NAME ], [ $method, \@_ ]);
    }
}

sub DESTROY {
}

1;

__END__

$wight->jQuery('.entry')->has('li')->click(sub { e => 'e.stop()' });
