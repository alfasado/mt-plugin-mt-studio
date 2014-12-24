<?php
function smarty_modifier_convert2base64( $src ) {
    if ( file_exists( $src ) ) {
        require_once( 'class.mt_session.php' );
        $session = new Session;
        $id = 'base64:' . md5( $src );
        $where = "session_id='$id' and session_kind='B6'";
        $cache = $session->Find( $where );
        $cache_exists;
        if ( isset( $cache ) ) {
            $cache_exists = 1;
            $cache = $cache[ 0 ];
            $update = filemtime( $src );
            if ( $update > $cache->start ) {
            } else {
                return $cache->data;
            }
        } else {
            $cache = $session;
        }
        $cache->session_id = $id;
        $cache->kind = 'B6';
        $cache->start = time();
        $data = base64_encode( file_get_contents( $src ) );
        $cache->data = $data;
        if ( $cache_exists ) {
            $cache->Update();
        } else {
            $cache->Save();
        }
        return $data;
    }
}
?>