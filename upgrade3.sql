-- Accepter davantage de formats vidéo à l'envoi. À exécuter après upgrade2.sql.
update storage.buckets set allowed_mime_types=array['video/mp4','video/webm','video/quicktime','video/x-matroska','video/x-msvideo','video/ogg','video/3gpp','video/mpeg','video/x-m4v'] where id='videos';
