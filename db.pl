use DBSQL;

1;

sub GovDBOpen {
	#      database,   username,   password
	if (!$ENV{REMOTE_DB}) {
		DBSQL::Open("govtrack", "root", "");
	} else {
		DBSQL::Open("database=govtrack;host=govtrack.us", "govtrack_sandbox", "");
	}
}

sub DBClose { DBSQL::Close(); }
sub DBSelectByID { return DBSQL::SelectByID(@_); }
sub DBSelectFirst { return DBSQL::SelectFirst(@_); }
sub DBSelectAll { return DBSQL::SelectAll(@_); }
sub DBSelectVector { return DBSQL::SelectVector(@_); }
sub DBSelectVectorDistinct { return DBSQL::SelectVectorDistinct(@_); }
sub DBSelect { return DBSQL::Select(@_); }
sub DBExecuteSelect { return DBSQL::ExecuteSelect(@_); }
sub DBDelete { return DBSQL::Delete(@_); }
sub DBDeleteByID { return DBSQL::DeleteByID(@_); }
sub DBInsert { return DBSQL::Insert(@_); }
sub DBUpdate { return DBSQL::Update(@_); }
sub DBUpdateByID { return DBSQL::UpdateByID(@_); }
sub DBExecute { return DBSQL::Execute(@_); }
sub DBEscape { return DBSQL::Escape(@_); }
sub DBSpecEQ { return DBSQL::SpecEQ(@_); }
sub DBSpecNE { return DBSQL::SpecNE(@_); }
sub DBSpecLE { return DBSQL::SpecLE(@_); }
sub DBSpecGE { return DBSQL::SpecGE(@_); }
sub DBSpecLT { return DBSQL::SpecLT(@_); }
sub DBSpecGT { return DBSQL::SpecGT(@_); }
sub DBSpecContains { return DBSQL::SpecContains(@_); }
sub DBSpecStartsWith { return DBSQL::SpecStartsWith(@_); }
sub DBSpecEndsWith { return DBSQL::SpecEndsWith(@_); }
sub DBSpec { return DBSQL::Spec(@_); }
sub DBSpecNot { return DBSQL::SpecNot(@_); }
sub DBSpecOrNull { return DBSQL::SpecOrNull(@_); }
sub DBSpecIn { return DBSQL::SpecIn(@_); }
sub MakeDBDate { return DBSQL::MakeDBDate(@_); }
sub GetDBDate { return DBSQL::GetDBDate(@_); }
sub GetDBTimestamp { return DBSQL::GetDBTimestamp(@_); }
