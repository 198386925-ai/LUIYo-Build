<?php
declare(strict_types=1);
http_response_code(410);
header('Cache-Control: no-store');
header('Content-Type: application/json; charset=utf-8');
echo json_encode(['error'=>'udid_mode_removed'], JSON_UNESCAPED_UNICODE);
