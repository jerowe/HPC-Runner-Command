requires 'perl', '5.008005';

requires "Algorithm::Dependency" , "0";
requires "Algorithm::Dependency::Source::HoA" , "0";
requires "Archive::Tar" , "0";
requires "Cwd" , "0";
requires "DBM::Deep" , "0";
requires "Data::Dumper" , "0";
requires "DateTime" , "0";
requires "DateTime::Format::Duration" , "0";
requires "File::Basename" , "0";
requires "File::Path" , "0";
requires "File::Slurp" , "0";
requires "File::Spec" , "0";
requires "File::Temp" , "0";
requires "Git::Wrapper" , "0";
requires "Git::Wrapper::Plus::Branches" , "0";
requires "Git::Wrapper::Plus::Ref::Tag" , "0";
requires "Git::Wrapper::Plus::Tags" , "0";
requires "IO::File" , "0";
requires "IO::Interactive" , "0";
requires "IO::Select" , "0";
requires "IPC::Cmd" , "0";
requires "IPC::Open3" , "0";
requires "JSON" , "0";
requires "List::MoreUtils" , "0";
requires "List::Util" , "0";
requires "Log::Log4perl" , "0";
requires "MCE" , "0";
requires "MCE::Queue" , "0";
requires "Moose" , "0";
requires "Moose::Role" , "0";
requires "Moose::Util::TypeConstraints" , "0";
requires "MooseX::App" , "0";
requires "MooseX::App::Command" , "0";
requires "MooseX::App::Role" , "0";
requires "MooseX::App::Role::Log4perl" , "0";
requires "MooseX::Object::Pluggable" , "0";
requires "MooseX::Types::Path::Tiny" , "0";
requires "Perl::Version" , "0";
requires "Sort::Versions" , "0";
requires "Storable" , "0";
requires "Symbol" , "0";
requires "Template" , "0";
requires "Try::Tiny" , "0";
requires "YAML::XS" , "0";
requires "namespace::autoclean" , "0";

on test => sub {
    requires "Test::More";
    requires "Capture::Tiny";
    requires "File::Slurp";
    requires "FindBin";
    requires "Slurp";
    requires "Test::Class::Moose";
    requires "Test::Class::Moose::Load";
    requires "Test::Class::Moose::Runner";
    requires "Text::Diff";
};
