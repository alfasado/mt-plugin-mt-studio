<?php
require_once( 'class.baseobject.php' );
class MTMLJob extends BaseObject
{
    public $_table = 'mt_mtmljob';
    protected $_prefix = "mtmljob_";
    protected $_has_meta = TRUE;
}
ADODB_Active_Record::ClassHasMany('MTMLJob', 'mt_mtmljob_meta','mtmljob_meta_mtmljob_id');
?>