'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"favicon.png": "cc9b028d3dd32d9fb7022d3c927c5245",
"canvaskit/canvaskit.js": "8331fe38e66b3a898c4f37648aaf7ee2",
"canvaskit/skwasm_heavy.js": "740d43a6b8240ef9e23eed8c48840da4",
"canvaskit/skwasm_heavy.wasm": "b0be7910760d205ea4e011458df6ee01",
"canvaskit/chromium/canvaskit.js": "a80c765aaa8af8645c9fb1aae53f9abf",
"canvaskit/chromium/canvaskit.js.symbols": "e2d09f0e434bc118bf67dae526737d07",
"canvaskit/chromium/canvaskit.wasm": "a726e3f75a84fcdf495a15817c63a35d",
"canvaskit/skwasm.js": "8060d46e9a4901ca9991edd3a26be4f0",
"canvaskit/canvaskit.js.symbols": "a3c9f77715b642d0437d9c275caba91e",
"canvaskit/skwasm_heavy.js.symbols": "0755b4fb399918388d71b59ad390b055",
"canvaskit/skwasm.wasm": "7e5f3afdd3b0747a1fd4517cea239898",
"canvaskit/skwasm.js.symbols": "3a4aadf4e8141f284bd524976b1d6bdc",
"canvaskit/wimp.js": "40195751139ab9e4b7c62b19c420f63b",
"canvaskit/canvaskit.wasm": "9b6a7830bf26959b200594729d73538e",
"canvaskit/wimp.wasm": "bd9945e051eaff19b80c59dca4f00e66",
"canvaskit/experimental_webparagraph/canvaskit.js": "230c0e2b182dcd1061c06c2fe7b64b5f",
"canvaskit/experimental_webparagraph/canvaskit.js.symbols": "0c6d97b036dffdc0f4bc4552ae7b5c9d",
"canvaskit/experimental_webparagraph/canvaskit.wasm": "e008e87c245b0718932b34e9a15be803",
"canvaskit/wimp.js.symbols": "c92db48c68aa42a16de0e2cd0ace9b9a",
"flutter_bootstrap.js": "6b894258b9c5bcba3a458f2f9c44776a",
"assets/NOTICES": "75d9fac71087c9b2684d5a3045559d2a",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/AssetManifest.bin": "bff46bb13206d0b1979a5b1c90e77f9b",
"assets/assets/audio/music_normal_01.wav": "ef58e33db47e17f053422d07aca8d0ab",
"assets/assets/audio/music_normal_08.wav": "807154a6620c6ad9b56e954c1b29e925",
"assets/assets/audio/music_normal_11.wav": "cc952ac2f32b8fc052a22d284d269230",
"assets/assets/audio/music_normal_03.wav": "518d72bb1b3abb51d607e8533ec11a79",
"assets/assets/audio/music_normal_14.wav": "9dd0f9fe3d1802cf64f283a254e446c9",
"assets/assets/audio/music_threat.wav": "6b337a4236ea38503f199ba7d3625752",
"assets/assets/audio/shoot.wav": "97910e7b48dc803f64526ede5c5b02d8",
"assets/assets/audio/music_normal_04.wav": "60814d539b8dabcb26f0f1085b0aa047",
"assets/assets/audio/music_normal_07.wav": "ed1b390dcf9d82415d5e7a5062f56a5b",
"assets/assets/audio/hit.wav": "dac7d1b8d1816b0e0f6f10d39a20977b",
"assets/assets/audio/music_normal_09.wav": "920943df521cabc288d559a81799a2bd",
"assets/assets/audio/music_normal_06.wav": "83e0402feae3d1a121ac915d1872f480",
"assets/assets/audio/music_normal_13.wav": "5d238f782d82fbf4e6aad565359de2af",
"assets/assets/audio/music_normal_05.wav": "4a7f7201c6f48fee951c36dc090a6b9d",
"assets/assets/audio/music_normal_10.wav": "3c92ee1cb598707c78bf5fe35b8a560e",
"assets/assets/audio/music_normal_15.wav": "f50a61a3bd9faa541f2c5cba9235eec4",
"assets/assets/audio/music_normal_02.wav": "cbf7a1d6bb0427b60f974084993f4b98",
"assets/assets/audio/build.wav": "53d9824a0ef04bd51c702b5c330ccfd4",
"assets/assets/audio/explosion.wav": "e973ec516f5ecffa6fd0c3564aee7b8d",
"assets/assets/audio/music_normal_12.wav": "417ed1e13520eacdb49aa95773dda78d",
"assets/assets/fonts/Orbitron.ttf": "a4ff8249fc28b57cab2c57139c5a4bcd",
"assets/FontManifest.json": "d0b9b5c58c747f0bbaf89b9fd0b895af",
"assets/fonts/MaterialIcons-Regular.otf": "6b29d5cd1e49b848d35556ed3820e852",
"assets/AssetManifest.bin.json": "f709b7b3369ed3e0421f5907840a219c",
"assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"index.html": "b49ee8ce081b7b5f365372875972ca2e",
"/": "b49ee8ce081b7b5f365372875972ca2e",
"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"main.dart.js": "cba765664fc9d322b5ee2c9895ba4476",
"manifest.json": "11d94a933df045af86ea50e03d172751",
"icons/Icon-512.png": "2291aef4e230b7543f103dc253cd0ed9",
"icons/Icon-maskable-512.png": "2291aef4e230b7543f103dc253cd0ed9",
"icons/Icon-maskable-192.png": "3148293ea50eb2040e9db3c513edb9da",
"icons/Icon-192.png": "3148293ea50eb2040e9db3c513edb9da",
"version.json": "5d39eafa7815ec3e097f001e2ffac19c"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
