<?php
declare(strict_types=1);

/** Verify both the CMS content signature and a pinned Apple device-CA signature.
 * Apple documents that device identity certificate validity dates are ignored in
 * this protocol. Never use NOVERIFY without the separate pinned-issuer check.
 * Unknown Apple device CA generations fail closed until the trust pin is updated.
 */
function luiyo_verify_device_payload(string $der): array {
    if(strlen($der)<32 || strlen($der)>65536)throw new RuntimeException('invalid_payload');
    $files=[];
    try {
        foreach(['cms','signer','content'] as $key){$path=tempnam(sys_get_temp_dir(),'luiyo-');if($path===false)throw new RuntimeException('temporary_file_failed');chmod($path,0600);$files[$key]=$path;}
        file_put_contents($files['cms'],$der);
        if(!openssl_cms_verify($files['cms'],OPENSSL_CMS_BINARY|OPENSSL_CMS_NOVERIFY,$files['signer'],[],null,$files['content'],null,null,OPENSSL_ENCODING_DER))throw new RuntimeException('signature_invalid');
        $pem=(string)file_get_contents($files['signer']);
        preg_match_all('/-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----/',$pem,$certs);
        if(count($certs[0])!==1)throw new RuntimeException('unexpected_signers');
        $signer=openssl_x509_read($certs[0][0]);$anchor=openssl_x509_read((string)file_get_contents(__DIR__.'/apple-device-ca.pem'));
        if(!$signer||!$anchor)throw new RuntimeException('certificate_invalid');
        $leaf=openssl_x509_parse($signer);$ca=openssl_x509_parse($anchor);
        if(($leaf['issuer']??null)!==($ca['subject']??null) || openssl_x509_verify($signer,openssl_pkey_get_public($anchor))!==1)throw new RuntimeException('untrusted_device_certificate');
        $xml=(string)file_get_contents($files['content']);
        if(strlen($xml)>16384||stripos($xml,'<!ENTITY')!==false)throw new RuntimeException('invalid_xml');
        $doc=new DOMDocument();$old=libxml_use_internal_errors(true);
        try{$ok=$doc->loadXML($xml,LIBXML_NONET);libxml_clear_errors();}finally{libxml_use_internal_errors($old);}
        if(!$ok||$doc->documentElement?->tagName!=='plist')throw new RuntimeException('invalid_plist');
        $xpath=new DOMXPath($doc);$dicts=$xpath->query('/plist/dict');if($dicts->length!==1)throw new RuntimeException('invalid_plist');
        $elements=[];foreach($dicts->item(0)->childNodes as $node)if($node instanceof DOMElement)$elements[]=$node;
        if(count($elements)%2!==0)throw new RuntimeException('invalid_plist');$values=[];
        for($i=0;$i<count($elements);$i+=2){
            if($elements[$i]->tagName!=='key'||$elements[$i+1]->tagName!=='string')throw new RuntimeException('invalid_plist_value');
            $key=$elements[$i]->textContent;if(isset($values[$key]))throw new RuntimeException('duplicate_key');$values[$key]=$elements[$i+1]->textContent;
        }
        $udid=strtoupper($values['UDID']??'');
        if(!preg_match('/^(?:[A-F0-9]{40}|[A-F0-9]{8}-[A-F0-9]{16})$/D',$udid)||!preg_match('/^[a-f0-9]{64}$/D',$values['CHALLENGE']??''))throw new RuntimeException('invalid_device_attributes');
        return ['udid'=>$udid,'challenge'=>$values['CHALLENGE']];
    }finally{foreach($files as $file)if(is_file($file))unlink($file);}
}
