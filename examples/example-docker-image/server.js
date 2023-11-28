const http = require('http');
const process = require('process');
const spawn = require('child_process').spawnSync;
const fs = require('fs');

const hostname = '0.0.0.0';
const port = 3000;
const bootDelaySec = process.env.BOOT_DELAY_SEC || 0;

var cachedServerText = null;

const server = http.createServer((req, res) => {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/plain');

  cachedServerText = cachedServerText || getServerText();
  res.end(cachedServerText + '\n');
});

function getServerText() {
  if (process.env.S3_TEST_FILE && process.env.SERVER_TEXT) {
    // Download the S3 File
    const output = spawn("aws", ["s3", "cp", process.env.S3_TEST_FILE, "-"]);
    if (output.status == 0) {
      return process.env.SERVER_TEXT + " " + output.stdout;
    } else {
      console.error(`ERROR: Unable to download s3 test file: ${process.env.S3_TEST_FILE}`);
      console.error("status: " + (output.status ? output.status.toString() : "(no status)"));
      console.error("stdout: " + (output.stdout ? output.stdout.toString('utf8') : "(no stdout)"));
      console.error("stderr: " + (output.stderr ? output.stderr.toString('utf8') : "(no stderr)"));
      console.error("error message:  " + (output.error ? output.error.message : "(no error message defined)"));
      throw output.error;
    }
  } else if (process.env.EFS_TEST_FILE && process.env.SERVER_TEXT) {
    try {
      // Write file to EFS storage
      fs.writeFileSync(process.env.EFS_TEST_FILE, process.env.SERVER_TEXT);
      // Read file from EFS storage
      return fs.readFileSync(process.env.EFS_TEST_FILE, 'utf8');
    } catch (err) {
      console.error(`ERROR: Unable to write/read EFS test file: ${process.env.EFS_TEST_FILE}`);
      throw err;
    }
  } else {
    return "Hello world!";
  }
}

// We introduce a controllable delay in the boot sequence so that you can test certain deployment scenarios and how ECS
// behaves. For example, you can set a long boot delay and then have the server crash by pointing to an S3_TEST_FILE
// that doesn't exist, to test the situation where the server passes the active task count check, but fails the load
// balancer check.
console.log(`Delaying boot by ${bootDelaySec} seconds`);
setTimeout(() => {
    server.listen(port, hostname, () => {
      console.log(`Server running at http://${hostname}:${port}/`);
    });
}, bootDelaySec*1000)
