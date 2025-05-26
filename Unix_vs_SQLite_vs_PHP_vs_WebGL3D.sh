#!/usr/bin/env bash
# Mini 3D agenda with PHP + SQLite + WebGL
# Written by Andrea Giani

set -e

APP_NAME="agenda3d"
PHP_DIR="php-${PHP_VER}"
PHP_VER="8.4.7"
PHP_ZIP="php-${PHP_VER}-nts-Win32-vs17-x64.zip"
PHP_URL="https://windows.php.net/downloads/releases/${PHP_ZIP}"

echo "==> Creating project: $APP_NAME"
rm -rf "$APP_NAME" "$PHP_DIR"
mkdir -p "$APP_NAME"
cd "$APP_NAME"

echo "==> Downloading PHP..."
curl -LO "$PHP_URL"
unzip "$PHP_ZIP" -d "$PHP_DIR"

echo "==> Configuring PHP and SQLite3..."
cp "$PHP_DIR/php.ini-development" "$PHP_DIR/php.ini"

sed -i "s|;extension_dir = \"ext\"|extension_dir = \"ext\"|" "$PHP_DIR/php.ini"
sed -i "s|;extension=sqlite3|extension=sqlite3|" "$PHP_DIR/php.ini"

if [ ! -f "$PHP_DIR/ext/php_sqlite3.dll" ]; then
    echo "ERROR: php_sqlite3.dll not found in $PHP_DIR/ext/"
    exit 1
fi

echo "==> Generating index.php..."
cat > index.php <<'EOF'
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>3D Agenda</title>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>
  <style>body { margin:0; overflow:hidden }</style>
</head>
<body>
  <canvas id="canvas"></canvas>
  <script>
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(75, window.innerWidth/window.innerHeight, 0.1, 1000);
    const renderer = new THREE.WebGLRenderer({canvas:document.getElementById('canvas')});
    renderer.setSize(window.innerWidth, window.innerHeight);

    // Main cube
    const geometry = new THREE.BoxGeometry();
    const material = new THREE.MeshBasicMaterial({color: 0x0077ff});
    const cube = new THREE.Mesh(geometry, material);
    scene.add(cube);
    camera.position.z = 5;

    // Array to track 3D texts
    let textMeshes = [];

    function createSimpleText3D(text, position) {
      const textGroup = new THREE.Group();
      
      const textGeometry = new THREE.PlaneGeometry(text.length * 0.2, 0.6);
      const canvas = document.createElement('canvas');
      const context = canvas.getContext('2d');
      canvas.width = 512;
      canvas.height = 128;
      
      // Random background color
      const randomR = Math.floor(Math.random() * 256);
      const randomG = Math.floor(Math.random() * 256);
      const randomB = Math.floor(Math.random() * 256);
      const backgroundColor = `rgb(${randomR},${randomG},${randomB})`;
      
      context.fillStyle = backgroundColor;
      context.fillRect(0, 0, canvas.width, canvas.height);
      
      // Text color (white or black for contrast)
      const brightness = (randomR + randomG + randomB) / 3;
      const textColor = brightness > 128 ? '#000000' : '#ffffff';
      
      context.fillStyle = textColor;
      context.font = 'bold 40px Arial';
      context.textAlign = 'center';
      context.fillText(text, canvas.width/2, canvas.height/2 + 15);
      
      const texture = new THREE.CanvasTexture(canvas);
      const textMaterial = new THREE.MeshBasicMaterial({
        map: texture,
        transparent: true
      });
      
      const textMesh = new THREE.Mesh(textGeometry, textMaterial);
      textMesh.position.set(position.x, position.y, position.z);
      
      scene.add(textMesh);
      textMeshes.push(textMesh);
      
      return textMesh;
    }

    function loadExistingEvents() {
      // Clear all existing 3D texts
      textMeshes.forEach(mesh => scene.remove(mesh));
      textMeshes = [];
      
      // Read events from database via AJAX
      fetch('get_events.php')
        .then(response => response.json())
        .then(events => {
          // Limit to maximum 6 visible events
          const maxEvents = 6;
          const eventsToShow = events.slice(0, maxEvents);
          
          eventsToShow.forEach((event, index) => {
            // Arrange in 2 rows of 3 columns max
            const col = index % 3;
            const row = Math.floor(index / 3);
            
            createSimpleText3D(event, {
              x: (col - 1) * 3,        // -3, 0, 3
              y: -2 - (row * 1.2),     // -2, -3.2 (only 2 rows)
              z: 0
            });
          });
        })
        .catch(error => console.log('Error loading events:', error));
    }

    function animate() {
      requestAnimationFrame(animate);
      cube.rotation.x += 0.01;
      cube.rotation.y += 0.01;
      
      textMeshes.forEach((mesh, index) => {
        mesh.rotation.y = Math.sin(Date.now() * 0.001 + index) * 0.1;
      });
      
      renderer.render(scene, camera);
    }
    animate();

    function changeColor() {
      const randomColor = 0x000000 + Math.floor(Math.random() * 0xffffff);
      cube.material.color.setHex(randomColor);
      setTimeout(changeColor, 1000);
    }
    changeColor();

    // Load events when page is fully loaded
    window.addEventListener('load', () => {
      setTimeout(loadExistingEvents, 100);
    });

  </script>

  <div style="position:fixed;top:10px;left:10px;background:rgba(255,255,255,0.9);padding:5px;border-radius:5px;">
    <form method="post" onsubmit="setTimeout(() => { location.reload(); }, 100)">
      <input name="msg" placeholder="Write event..." required>
      <button type="submit">Save</button>
    </form>
    <div><strong>Saved events:</strong><br>
    <div class="events-list" style="max-height:200px;overflow-y:auto;">
    <?php
    $db = new SQLite3('agenda.db');
    $db->exec('CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY, text TEXT)');
    if (!empty($_POST['msg'])) {
      $stmt = $db->prepare('INSERT INTO events (text) VALUES (:msg)');
      $stmt->bindValue(':msg', $_POST['msg'], SQLITE3_TEXT);
      $stmt->execute();
    }
    $res = $db->query('SELECT text FROM events ORDER BY id DESC LIMIT 6');
    while ($row = $res->fetchArray()) {
      echo htmlspecialchars($row['text']) . "<br>";
    }
    ?>
    </div>
    </div>
  </div>
</body>
</html>
EOF

echo "==> Generating get_events.php..."
cat > get_events.php <<'EOF'
<?php
header('Content-Type: application/json');
$db = new SQLite3('agenda.db');
$db->exec('CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY, text TEXT)');
$res = $db->query('SELECT text FROM events ORDER BY id DESC LIMIT 6');
$events = [];
while ($row = $res->fetchArray()) {
    $events[] = $row['text'];
}
echo json_encode($events);
?>
EOF

start http://localhost:8080/index.php

echo "==> Starting PHP server..."
"$(pwd)/$PHP_DIR/php.exe" -c "$(pwd)/$PHP_DIR/php.ini" -S localhost:8080