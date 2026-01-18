module version;

const VERSION = "@@VERSION@@";
const AUTHOR  = "@@AUTHOR@@";

$exec(`echo "const GIT_HASH = \"$(git rev-parse HEAD)\";"`) @if(env::POSIX);
$exec(`for /f "delims=" %a in ('git rev-parse HEAD') do @echo const GIT_HASH = "%a";`) @if(env::WIN32);
