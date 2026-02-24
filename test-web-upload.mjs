import fs from 'fs';
import path from 'path';

async function testUpload() {
  const fileContent = "dummy image data";
  const blob = new Blob([fileContent], { type: 'image/jpeg' });
  const fd = new FormData();
  fd.append("file", blob, "test.jpg");

  try {
    const res = await fetch("http://localhost:3000/api/upload", {
      method: "POST",
      body: fd,
      // No auth header = Should hit 401
    });
    console.log("Status without Auth:", res.status);

    // Let's examine if a valid JWT token from the db allows upload.
    // Wait, testing via curl/node requires a valid JWT which I can't easily mock here.
    // I will check the Vercel logs or NEXT logs instead.

  } catch (err) {
    console.error(err);
  }
}

testUpload();
