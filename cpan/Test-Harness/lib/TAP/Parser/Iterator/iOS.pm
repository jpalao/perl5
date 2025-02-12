package TAP::Parser::Iterator::iOS;

use strict;
use warnings;
use Data::Dumper;
use Cwd qw/getcwd/;
use ios;

use base 'TAP::Parser::Iterator';

=head1 NAME

TAP::Parser::Iterator::iOS - Iterator for array TAP sources on iOS

=head1 VERSION

Version 3.43

=cut

our $VERSION = '3.43';

=head1 SYNOPSIS

  use TAP::Parser::Iterator::iOS;
  my @data = ('foo', 'bar', baz');
  my $it   = TAP::Parser::Iterator::iOS->new(\@data);
  my $line = $it->next;

=head1 DESCRIPTION

This is a simple iterator wrapper for arrays of scalar content, used by
L<TAP::Parser> and modified to be used on iOS.  Unless you're writing a
plugin or subclassing, you probably won't need to use this module directly.

=head1 METHODS

=head2 Class Methods

=head3 C<new>

Create an iterator.  Takes one argument: an C<$array_ref>

=head2 Instance Methods

=head3 C<next>

Iterate through it, of course.

=head3 C<next_raw>

Iterate raw input without applying any fixes for quirky input syntax.

=head3 C<wait>

Get the wait status for this iterator. For an array iterator this will always
be zero.

=head3 C<exit>

Get the exit status for this iterator. For an array iterator this will always
be zero.

=cut

# new() implementation supplied by TAP::Object

sub array_ref_from {
    my $string = shift;
    my @lines = split /\n/ => $string;
    return \@lines;
}

sub _initialize {
    my ( $self, $thing ) = @_;

    my $workdir = getcwd();
    my ($exit_code, $tap);
    if (ref $thing eq 'ARRAY') {
        chomp @$thing;
        my $command = join " ", @$thing;
        ($exit_code, $tap) = exec_test($workdir, $command);
        $self->{array} = array_ref_from($tap);
        $self->{exit}  = $exit_code;
    }
    chdir $workdir;
    $self->{idx}   = 0;
    return $self;
}

sub wait { shift->exit }

sub exit {
    my $self = shift;
    return 0 if $self->{array} && $self->{idx} >= @{ $self->{array} };
    return;
}

sub next_raw {
    my $self = shift;
    return $self->{array}->[ $self->{idx}++ ];
}

1;

=head1 ATTRIBUTION

Ripped off from L<TAP::Parser::Iterator::Array>.

=head1 SEE ALSO

L<TAP::Object>,
L<TAP::Parser>,
L<TAP::Parser::Iterator>,

=cut

