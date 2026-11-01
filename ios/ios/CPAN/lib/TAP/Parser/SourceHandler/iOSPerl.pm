package TAP::Parser::SourceHandler::iOSPerl;

use strict;
use warnings;

use TAP::Parser::Iterator::iOS;
use TAP::Parser::IteratorFactory ();

use base 'TAP::Parser::SourceHandler::Perl';

TAP::Parser::IteratorFactory->register_handler(__PACKAGE__);

sub can_handle {
    my ($class, $source) = @_;
    my $vote = $class->SUPER::can_handle($source);
    return $vote ? $vote + 0.001 : 0;
}

my $op_paused;

# iOS may kill the harness for sustained CPU usage during t/op, so pause
# once before the first op/ test. PERL_IOS_OP_PAUSE=0 disables the pause.
sub _pause_before_op {
    my ($source) = @_;
    return if $op_paused;
    my $file = ${ $source->raw };
    return unless defined $file && $file =~ m{^op/};
    $op_paused = 1;
    my $seconds = $ENV{PERL_IOS_OP_PAUSE} // 180;
    return unless $seconds > 0;
    print "# iOS: pausing ${seconds}s before op/ tests\n";
    sleep $seconds;
}

sub _create_iterator {
    my ($class, $source, $command, $setup, $teardown) = @_;

    _pause_before_op($source);

    return TAP::Parser::Iterator::iOS->new({
        command  => $command,
        merge    => $source->merge,
        setup    => $setup,
        teardown => $teardown,
    });
}

1;
