const fs = require('fs');

async function testUpload() {
  const fileContent = "dummy image data";
  const blob = new Blob([fileContent], { type: 'image/jpeg' });
  const fd = new FormData();
  fd.append("file", blob, "test.jpg");

  const res = await fetch("http://localhost:3000/api/upload", {
    method: "POST",
    body: fd
  });
  
  const json = await res.json();
  console.log("Status:", res.status);
  console.log("Response:", json);
}

testUpload().catch(console.error);
