package AnyEvent::StreamXML::Stanza;

use Scalar::Util 'blessed', 'refaddr';

use overload
	'bool'   => sub { 1 },
	'""'     => sub { $_[0]->toString() },
	'+0'     => sub { refaddr $_[0] },
	fallback => 1,
;

use uni::perl ':dumper';
no strict 'refs';
use XML::Fast;

use AnyEvent::StreamXML::Stanza::NULL;
use AnyEvent::StreamXML::Stanza::ARRAY;


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
	$_[0][1]{'-'.$_[1]}
}
sub value {
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

our $AUTOLOAD;
sub  AUTOLOAD {
	my $n = substr($AUTOLOAD, rindex($AUTOLOAD,':') + 1);
	#warn "$n(@_)";
	#warn "$AUTOLOAD -> $n";
	if (exists $_[0][1]{ $n }) {
		*{ $n } = sub {
			if( exists $_[0][1]{ $n } ) {
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
					return wantarray
						? map { AnyEvent::StreamXML::Stanza->newn( $n,$_ ) } @$x
						: AnyEvent::StreamXML::Stanza::ARRAY->new([ map { AnyEvent::StreamXML::Stanza->newn( $n,$_ ) } @$x ])
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
		goto &{ $n };
	}
	else {
		return AnyEvent::StreamXML::Stanza::NULL->new;
	}
}
sub DESTROY {}

1;
