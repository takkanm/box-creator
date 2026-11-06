// Three.js preview. STL bytes are shown as they will print; the lid is turned
// back over here to sit on the base.
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { toCreasedNormals } from 'three/addons/utils/BufferGeometryUtils.js';

const BASE_COLOR = 0x4fae7f;
const LID_COLOR = 0x8d6fd6;
const CREASE_ANGLE = Math.PI / 6;
const SMOOTH_LIMIT = 40000; // triangles; beyond this, keep the flat STL normals

function parseStl(buffer) {
  const view = new DataView(buffer);
  const count = view.getUint32(80, true);
  const positions = new Float32Array(count * 9);
  const normals = new Float32Array(count * 9);
  for (let i = 0; i < count; i++) {
    const at = 84 + i * 50;
    for (let v = 0; v < 3; v++) {
      for (let a = 0; a < 3; a++) {
        normals[i * 9 + v * 3 + a] = view.getFloat32(at + a * 4, true);
        positions[i * 9 + v * 3 + a] = view.getFloat32(at + 12 + v * 12 + a * 4, true);
      }
    }
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geometry.setAttribute('normal', new THREE.BufferAttribute(normals, 3));
  return count <= SMOOTH_LIMIT ? toCreasedNormals(geometry, CREASE_ANGLE) : geometry;
}

// One printed part plus what it takes to fill its cut face in section view.
class Part {
  constructor(scene, color, order, plane, renderer) {
    this.group = new THREE.Group();
    scene.add(this.group);
    this.plane = plane;
    this.material = new THREE.MeshStandardMaterial({ color, roughness: 0.62, metalness: 0.02, side: THREE.DoubleSide });
    this.mesh = new THREE.Mesh(new THREE.BufferGeometry(), this.material);
    this.mesh.renderOrder = 10;
    this.group.add(this.mesh);

    const stencil = (side, op) => new THREE.MeshBasicMaterial({
      depthWrite: false, depthTest: false, colorWrite: false, side,
      stencilWrite: true, stencilFunc: THREE.AlwaysStencilFunc,
      stencilFail: op, stencilZFail: op, stencilZPass: op,
      clippingPlanes: [plane],
    });
    this.back = new THREE.Mesh(this.mesh.geometry, stencil(THREE.BackSide, THREE.IncrementWrapStencilOp));
    this.front = new THREE.Mesh(this.mesh.geometry, stencil(THREE.FrontSide, THREE.DecrementWrapStencilOp));
    this.back.renderOrder = order;
    this.front.renderOrder = order;
    this.group.add(this.back, this.front);

    this.cap = new THREE.Mesh(
      new THREE.PlaneGeometry(1, 1),
      new THREE.MeshStandardMaterial({
        color: new THREE.Color(color).multiplyScalar(0.72), roughness: 0.85,
        stencilWrite: true, stencilRef: 0, stencilFunc: THREE.NotEqualStencilFunc,
        stencilFail: THREE.ReplaceStencilOp, stencilZFail: THREE.ReplaceStencilOp, stencilZPass: THREE.ReplaceStencilOp,
      }),
    );
    this.cap.renderOrder = order + 0.5;
    this.cap.onAfterRender = () => renderer.clearStencil();
    scene.add(this.cap);
    this.setSection(false);
  }

  setGeometry(geometry) {
    this.mesh.geometry.dispose();
    this.mesh.geometry = geometry;
    this.back.geometry = geometry;
    this.front.geometry = geometry;
  }

  setSection(on) {
    this.material.clippingPlanes = on ? [this.plane] : [];
    this.material.needsUpdate = true;
    this.back.visible = on;
    this.front.visible = on;
    this.cap.visible = on;
  }
}

export class Preview {
  constructor(container) {
    this.container = container;
    this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, stencil: true });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.localClippingEnabled = true;
    container.prepend(this.renderer.domElement);

    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(32, 1, 1, 8000);
    this.camera.up.set(0, 0, 1);
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enableDamping = true;
    this.controls.addEventListener('change', () => this.requestRender());

    this.scene.add(new THREE.HemisphereLight(0xffffff, 0x8a8a84, 1.5));
    const key = new THREE.DirectionalLight(0xffffff, 1.6);
    key.position.set(1, -1.4, 2);
    this.camera.add(key);
    this.scene.add(this.camera);

    this.plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
    this.base = new Part(this.scene, BASE_COLOR, 1, this.plane, this.renderer);
    this.lid = new Part(this.scene, LID_COLOR, 2, this.plane, this.renderer);

    this.exploded = true;
    this.section = false;
    this.sectionPos = 0;
    this.height = 100;
    this.halfDepth = 30;
    this.radius = 0;

    new ResizeObserver(() => this.resize()).observe(container);
    this.resize();
    this.tick = this.tick.bind(this);
    requestAnimationFrame(this.tick);
  }

  // dims: { h, topZ, baseH }
  update(baseBuffer, lidBuffer, dims) {
    this.base.setGeometry(parseStl(baseBuffer));
    this.lid.setGeometry(parseStl(lidBuffer));
    this.height = dims.h;
    this.lift = dims.topZ - dims.baseH + dims.h * 0.22;
    this.base.mesh.geometry.computeBoundingBox();
    const box = this.base.mesh.geometry.boundingBox;
    this.halfDepth = box.max.y;
    this.halfWidth = box.max.x;
    this.placeLid();
    this.placeCaps();
    const radius = Math.hypot(box.max.x, box.max.y, dims.h / 2);
    if (this.radius === 0 || Math.abs(radius / this.radius - 1) > 0.25) this.frame(radius);
    this.radius = radius;
    this.requestRender();
  }

  placeLid() {
    const lift = this.exploded ? this.lift : 0;
    this.lid.group.rotation.set(Math.PI, 0, 0);
    this.lid.group.position.set(0, 0, this.height + lift);
  }

  placeCaps() {
    const size = 4 * Math.max(this.halfWidth || 50, this.height);
    for (const part of [this.base, this.lid]) {
      part.cap.scale.set(size, size, 1);
      part.cap.quaternion.setFromUnitVectors(new THREE.Vector3(0, 0, 1), new THREE.Vector3(0, -1, 0));
      part.cap.position.set(0, this.sectionPos * this.halfDepth, this.height / 2);
    }
    this.plane.constant = -this.sectionPos * this.halfDepth;
  }

  frame(radius = this.radius) {
    const totalHeight = this.height + (this.exploded ? this.lift : 0);
    this.controls.target.set(0, 0, totalHeight / 2);
    const distance = Math.max(radius, totalHeight * 0.62) / Math.sin((this.camera.fov / 2) * Math.PI / 180) * 1.12;
    const direction = new THREE.Vector3(0.62, -1, 0.5).normalize();
    this.camera.position.copy(this.controls.target).addScaledVector(direction, distance);
    this.controls.update();
    this.requestRender();
  }

  setExploded(on) {
    this.exploded = on;
    this.placeLid();
    this.controls.target.z = (this.height + (on ? this.lift : 0)) / 2;
    this.requestRender();
  }

  setSection(on) {
    this.section = on;
    this.base.setSection(on);
    this.lid.setSection(on);
    this.requestRender();
  }

  setSectionPos(value) {
    this.sectionPos = value;
    this.placeCaps();
    this.requestRender();
  }

  resize() {
    const { clientWidth: w, clientHeight: h } = this.container;
    if (w === 0 || h === 0) return;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.requestRender();
  }

  requestRender() {
    this.dirty = true;
  }

  tick() {
    this.controls.update();
    if (this.dirty) {
      this.dirty = false;
      this.renderer.render(this.scene, this.camera);
    }
    requestAnimationFrame(this.tick);
  }
}
