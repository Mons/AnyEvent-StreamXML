package AnyEvent::StreamXML::XMPP::Message;

use parent 'AnyEvent::StreamXML::XMPP::Stanza';

sub body { shift->child('body')->value  }

1;
