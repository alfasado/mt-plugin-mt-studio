<?php
require_once( 'class.baseobject.php' );
class Property extends BaseObject
{
    public $_table = 'mt_property';
    protected $_prefix = "property_";
    public function Save() {
        $mt = MT::get_instance();
        $driver = $mt->config( 'ObjectDriver' );
        if ( strpos( $driver, 'SQLServer' ) !== FALSE ) {
            // UMSSQLServer
            $prefix = $this->_prefix;
            $table = $this->_table;
            $sql = 'select max(' . $prefix . 'id) from ' . $table;
            $res = $mt->db()->Execute( $sql );
            $max = $res->_array[ 0 ][ '' ];
            $sql = 'SET IDENTITY_INSERT ' . $table . ' ON';
            $mt->db()->Execute( $sql );
            $max++;
            $this->id = $max;
            try {
                $this->Insert();
            } catch ( Exception $e ) {
                // $e->getMessage();
                $max += 10;
                $this->id = $max;
                try {
                    $res = $this->Insert();
                } catch ( Exception $e ) {
                }
            }
            $sql = 'SET IDENTITY_INSERT ' . $table . ' OFF';
            $mt->db()->Execute( $sql );
        } else {
            $res = parent::Save();
        }
    }
}
?>