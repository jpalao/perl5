package TAP::Parser::SourceHandler::iOSExecutable;

use strict;
use warnings;

use TAP::Parser::Iterator::iOS;
use TAP::Parser::IteratorFactory ();

use base 'TAP::Parser::SourceHandler::Executable';

TAP::Parser::IteratorFactory->register_handler(__PACKAGE__);

sub can_handle {
    my ($class, $source) = @_;
    my $vote = $class->SUPER::can_handle($source);
    return $vote ? $vote + 0.001 : 0;
}

sub iterator_class { 'TAP::Parser::Iterator::iOS' }

1;
