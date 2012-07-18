package AnyEvent::StreamXML::Stanza::ARRAY;

use overload
	'eq' => sub {
		my $av = shift;
		my $cmp = shift;
		for (@$av) {
			return 1 if $_ eq $cmp;
		}
		return 0;
	},
	fallback => 1;

sub new {
	my $pk = shift;
	return bless $_[0],$pk;
}

our $AUTOLOAD;
sub  AUTOLOAD {
	my $n = substr($AUTOLOAD, rindex($AUTOLOAD,':') + 1);
	*$n = sub {
		my $av = shift;
		my @a = map { $_->$n(@_) } @{ $av };
		if (wantarray) {
			return @a;
		} else {
			return + (ref $av)->new(\@a);
		}
	};
	goto &$n;
}
sub DESTROY {}

1;
