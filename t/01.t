use Test::Simple tests => 3;

require Win32::OLE;

ok(1);

use VSS;

ok(2);

ok(UNIVERSAL::isa(VSS->new(db_path => '', username => '', password => '')
			,'Win32::OLE'));
