package AnyEvent::StreamXML::Stanza;

use Scalar::Util ();

use overload
	'bool'   => sub { 1 },
	'""'     => sub { $_[0]->toString() },
	'+0'     => sub { Scalar::Util::refaddr $_[0] },
	'eq'     => sub {
		return $_[0]->value eq $_[1];
	},
	fallback => 1,
;

use uni::perl ':dumper';
no strict 'refs';
use XML::Fast;

use AnyEvent::StreamXML::Stanza::NULL;
use AnyEvent::StreamXML::Stanza::ARRAY;

our $AUTOLOAD;

sub new {
	my $pk = shift;
	my $ref = shift;
	return $pk->news($ref) unless ref $ref;
	my @n = (keys %$ref);
	@n != 1 and die "Only one root node allowed";
	return bless [ @n, $ref->{$n[0]} ],$pk;
}

sub news {
	my $pk = shift;
	$pk->new( xml2hash( $_[0] ) );
}

sub newn {
	my $pk = shift;
	return bless [ @_ ],$pk;
}

sub name {
	$_[0][0]
}
sub attr {
	if (@_ == 1) {
		return grep { substr($_,0,1,"") eq '-' } keys %{ $_[0][1] };
	}
	elsif (@_ == 3) {
		if (defined $_[2]) {
			$_[0][1]{'-'.$_[1]} = $_[2];
		} else {
			delete $_[0][1]{'-'.$_[1]};
		}
	}
	$_[0][1]{'-'.$_[1]}
}

sub children {
	my @x;
				if(UNIVERSAL::isa( $_[0][1],'HASH' )) {
					@x = map { AnyEvent::StreamXML::Stanza->newn( $_, $_[0][1]{$_} ) }
						grep { substr($_,0,1) ne '-' } keys %{ $_[0][1] };
				}
				elsif(UNIVERSAL::isa( $_[0][1],'ARRAY' )) {
					@x = map { AnyEvent::StreamXML::Stanza->newn( $_[0][0],$_ ) } @{ $_[0][1] };
				}
				else {
					@x = ( $_[0][1] );
				}
					return wantarray
						? @x
						: AnyEvent::StreamXML::Stanza::ARRAY->new(\@x);
	
}
sub child {
	if (ref $_[1]) {
		if(UNIVERSAL::isa( $_[0][1],'HASH' )) {
			@{ $_[0][1] }{ keys %{ $_[1] } } = values %{ $_[1] };
		}
		elsif(UNIVERSAL::isa( $_[0][1],'ARRAY' )) {
			push @{ $_[0][1] }, $_[1];
		}
	}
	elsif( $_[1] + 0 eq $_[1] ) {
		my $ref = $_[0]->children;
		exists $ref->[$_[1]]
			? $ref->[$_[1]]
			: AnyEvent::StreamXML::Stanza::NULL->new;
	}
	else {
		$AUTOLOAD = ref($_[0]).'::'.$_[1];
		goto &AUTOLOAD;
	}
}

sub value {
	#warn "call raw value on $_[0][1]";
	if (ref $_[0][1]) {
		return exists $_[0][1]{'#text'} ? $_[0][1]{'#text'} : '';
	}
	else {
		return $_[0][1];
	}
}

sub toString {
	hash2xml( +{ $_[0][0] => $_[0][1] } );
}

sub  AUTOLOAD {
	my $n = substr($AUTOLOAD, rindex($AUTOLOAD,':') + 1);
	#warn "$n(@_)";
	#warn "$AUTOLOAD -> $n ";#.dumper$_[0][1];
	if (exists $_[0][1]{ $n }) {
		my $sub = sub {
			if( exists $_[0][1]{ $n } ) {
				#warn "autoloaded $n on ".dumper $_[0][1];
				my $x = $_[0][1]{ $n };
				if (UNIVERSAL::isa( $x,'HASH' )) { 
					if (@_ > 1) {
						if ($x->{-xmlns} ne $_[1]) {
							return AnyEvent::StreamXML::Stanza::NULL->new;
						}
					}
					return AnyEvent::StreamXML::Stanza->newn( $n,$x );
				}
				elsif(UNIVERSAL::isa( $x,'ARRAY' )) {
					my @av =
						map { AnyEvent::StreamXML::Stanza->newn( $n,$_ ) }
						grep { @_ > 1 ? $_->{-xmlns} eq $_[1] : 1 }
					 	@$x;
					return wantarray
						? @av
						: AnyEvent::StreamXML::Stanza::ARRAY->new(\@av)
				}
				elsif (!ref $x) {
					return AnyEvent::StreamXML::Stanza->newn( $n,$x );
				}
				else {
					warn "XXX: ".dumper $x;
				}
			} else {
				return AnyEvent::StreamXML::Stanza::NULL->new;
			}
		};
		if ($n !~ /^(value|child|children|name|attr|toString)$/) {
			#warn "*$n = $sub";
			*{ $n } = $sub;
			goto &{ $n };
		} else {
			#warn "pure call of $n";
			goto &$sub;
		}
	}
	else {
		return AnyEvent::StreamXML::Stanza::NULL->new;
	}
}
sub DESTROY {}

1;
