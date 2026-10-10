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

sub _create_iterator {
    my ($class, $source, $command, $setup, $teardown) = @_;

    return TAP::Parser::Iterator::iOS->new({
        command  => $command,
        merge    => $source->merge,
        setup    => $setup,
        teardown => $teardown,
    });
}

1;
