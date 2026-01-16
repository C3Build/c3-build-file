module version;

const VERSION = "0.2.1";

$exec(`echo "const GIT_HASH = \"$(git rev-parse HEAD)\";"`);
