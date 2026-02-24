const fs = require('fs');
fetch('http://localhost:3000/api/upload', {
  method: 'POST',
  body: (() => {
    const fd = new FormData();
    fd.append('file', new Blob(["test image content"]), "test.jpg");
    return fd;
  })()
}).then(r => r.json()).then(console.log).catch(console.error);
