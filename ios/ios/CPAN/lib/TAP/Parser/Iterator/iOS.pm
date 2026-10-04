package TAP::Parser::Iterator::iOS;

use strict;
use warnings;
use Cwd qw(getcwd);
use ios;

use base 'TAP::Parser::Iterator';

=head1 NAME

TAP::Parser::Iterator::iOS - Iterator for embedded Perl TAP sources on iOS

=head1 VERSION

Version 3.43

=cut

our $VERSION = '3.43';

sub array_ref_from {
    my $string = shift;
    my @lines = split /\n/ => (defined $string ? $string : '');
    return \@lines;
}

sub _initialize {
    my ( $self, $thing ) = @_;

    my $workdir = getcwd();
    my ($exit_code, $tap);
    my $command_parts;
    my ($setup, $teardown);
    if (ref $thing eq 'HASH') {
        $command_parts = $thing->{command};
        $setup = $thing->{setup};
        $teardown = $thing->{teardown};
    } elsif (ref $thing eq 'ARRAY') {
        $command_parts = $thing;
    }

    if ($command_parts) {
        $setup->() if $setup;
        chomp @$command_parts;
        ($exit_code, $tap) = exec_test($workdir, $command_parts);
        $teardown->() if $teardown;
        if (defined $tap) {
            utf8::downgrade($tap, 1) if utf8::is_utf8($tap);
            utf8::decode($tap) unless utf8::is_utf8($tap);
        }
        $self->{array} = array_ref_from($tap);
        $self->{wait}  = $exit_code;
        $self->{exit}  = $exit_code >> 8;
    }
    chdir $workdir;
    $self->{idx} = 0;
    return $self;
}

sub wait { shift->{wait} }

sub exit { shift->{exit} }

sub next_raw {
    my $self = shift;
    return $self->{array}->[ $self->{idx}++ ];
}

1;
