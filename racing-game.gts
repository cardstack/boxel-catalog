import { multiply } from '@cardstack/boxel-ui/helpers';
import { concat } from '@ember/helper';
// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import {
  CardDef,
  FieldDef,
  field,
  contains,
  Component,
  linksTo,
} from 'https://cardstack.com/base/card-api'; // ¹ Core imports
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import BooleanField from 'https://cardstack.com/base/boolean';
import { Button, FieldContainer } from '@cardstack/boxel-ui/components'; // ² UI components
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { task, restartableTask, timeout } from 'ember-concurrency'; // ³ Async task handling
import Modifier from 'ember-modifier';
import RocketIcon from '@cardstack/boxel-icons/rocket'; // ⁴ Icon import

// ⁵ Car configuration field
export class CarConfig extends FieldDef {
  static displayName = 'Car Configuration';

  @field speed = contains(NumberField);
  @field acceleration = contains(NumberField);
  @field handling = contains(NumberField);
  @field color = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='car-config'>
        <div class='stat'>
          <span class='label'>Speed:</span>
          <span class='value'>{{@model.speed}}</span>
        </div>
        <div class='stat'>
          <span class='label'>Acceleration:</span>
          <span class='value'>{{@model.acceleration}}</span>
        </div>
        <div class='stat'>
          <span class='label'>Handling:</span>
          <span class='value'>{{@model.handling}}</span>
        </div>
        <div class='stat'>
          <span class='label'>Color:</span>
          <span class='value'>{{@model.color}}</span>
        </div>
      </div>

      <style scoped>
        .car-config {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 0.5rem;
          padding: 0.75rem;
          background: #f8fafc;
          border-radius: 0.5rem;
        }

        .stat {
          display: flex;
          justify-content: space-between;
          font-size: 0.875rem;
        }

        .label {
          font-weight: 500;
          color: #6b7280;
        }

        .value {
          font-weight: 600;
          color: #111827;
        }
      </style>
    </template>
  };
}

// ⁷ Three.js modifier for canvas setup
class ThreeJsModifier extends Modifier {
  element!: HTMLCanvasElement;
  racingGame: any;

  constructor(owner: unknown, args: {}) {
    super(owner, args);
  }

  modify(element: HTMLCanvasElement, [racingGame]: [any]) {
    this.element = element;
    this.racingGame = racingGame;
    this.setupThreeJs();
  }

  private async setupThreeJs() {
    if (!this.racingGame || !this.element) return;

    // Initialize the racing game with the canvas
    await this.racingGame.initializeGame(this.element);
  }
}

export class RacingGame extends CardDef {
  // ⁸ Main racing game card
  static displayName = 'Racing Game';
  static icon = RocketIcon;

  @field cardTitle = contains(StringField, {
    computeVia: function (this: RacingGame) {
      return this.gameName ?? 'Racing Game';
    },
  });

  @field gameName = contains(StringField); // ⁹ Primary fields
  @field cardDescription = contains(StringField);
  @field isGameActive = contains(BooleanField);
  @field carConfig = contains(CarConfig);
  @field raceMap = linksTo(() => import('./race-map').then((m) => m.RaceMap)); // ³⁴ Link to race map

  static isolated = class Isolated extends Component<typeof this> {
    // ¹⁰ Main game component
    @tracked scene: any = null;
    @tracked camera: any = null;
    @tracked renderer: any = null;
    @tracked car: any = null;
    @tracked track: any = null;
    @tracked gameStarted = false;
    @tracked currentSpeed = 0;
    @tracked currentLap = 1;
    @tracked lapTime = 0;
    @tracked gameTime = 0;
    @tracked bestLapTime = 0;

    // ¹¹ Car controls
    @tracked keys = {
      forward: false,
      backward: false,
      left: false,
      right: false,
      brake: false,
    };

    // ¹² Car physics properties
    carPosition = { x: 0, y: 0.5, z: 0 };
    carRotation = { x: 0, y: 0, z: 0 };
    carVelocity = { x: 0, y: 0, z: 0 };
    carSpeed = 0;
    maxSpeed = 2;
    acceleration = 0.05;
    friction = 0.95;
    turnSpeed = 0.03;

    // ¹³ Global accessor for Three.js
    get three() {
      return (globalThis as any).THREE;
    }

    // ¹⁴ Load Three.js library
    private loadThreeJs = task(async () => {
      if (this.three) return;

      const script = document.createElement('script');
      script.src =
        'https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.min.js';
      script.async = true;

      await new Promise((resolve, reject) => {
        script.onload = resolve;
        script.onerror = reject;
        document.head.appendChild(script);
      });

      await timeout(100); // Small delay for library initialization
    });

    // ¹⁵ Initialize the 3D racing game
    initializeGame = async (canvas: HTMLCanvasElement) => {
      try {
        await this.loadThreeJs.perform();
        if (!this.three || !canvas) return;

        const THREE = this.three;

        // Scene setup
        this.scene = new THREE.Scene();
        this.scene.background = new THREE.Color(0x87ceeb); // Sky blue

        // Camera setup (behind car view)
        this.camera = new THREE.PerspectiveCamera(
          75,
          canvas.clientWidth / canvas.clientHeight,
          0.1,
          1000,
        );

        // Renderer setup
        this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
        this.renderer.setSize(canvas.clientWidth, canvas.clientHeight);
        this.renderer.shadowMap.enabled = true;
        this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;

        // ¹⁶ Lighting
        const ambientLight = new THREE.AmbientLight(0x404040, 0.6);
        this.scene.add(ambientLight);

        const directionalLight = new THREE.DirectionalLight(0xffffff, 0.8);
        directionalLight.position.set(50, 50, 50);
        directionalLight.castShadow = true;
        directionalLight.shadow.mapSize.width = 2048;
        directionalLight.shadow.mapSize.height = 2048;
        this.scene.add(directionalLight);

        // ¹⁷ Create track
        this.createTrack();

        // ¹⁸ Create car
        this.createCar();

        // ¹⁹ Setup controls
        this.setupControls();

        // ²⁰ Start game loop
        this.startGameLoop();

        // Update model
        this.args.model.isGameActive = true;
      } catch (error) {
        console.error('Failed to initialize racing game:', error);
      }
    };

    // ²¹ Create racing track
    createTrack() {
      const THREE = this.three;

      // Track base (oval shape)
      const trackGeometry = new THREE.RingGeometry(15, 25, 32);
      const trackMaterial = new THREE.MeshLambertMaterial({ color: 0x333333 });
      this.track = new THREE.Mesh(trackGeometry, trackMaterial);
      this.track.rotation.x = -Math.PI / 2;
      this.track.receiveShadow = true;
      this.scene.add(this.track);

      // Inner grass
      const grassGeometry = new THREE.CircleGeometry(15, 32);
      const grassMaterial = new THREE.MeshLambertMaterial({ color: 0x228b22 });
      const innerGrass = new THREE.Mesh(grassGeometry, grassMaterial);
      innerGrass.rotation.x = -Math.PI / 2;
      innerGrass.position.y = -0.01;
      this.scene.add(innerGrass);

      // Outer grass
      const outerGrassGeometry = new THREE.CircleGeometry(35, 32);
      const outerGrass = new THREE.Mesh(outerGrassGeometry, grassMaterial);
      outerGrass.rotation.x = -Math.PI / 2;
      outerGrass.position.y = -0.02;
      this.scene.add(outerGrass);

      // ²² Track barriers
      const barrierGeometry = new THREE.BoxGeometry(1, 2, 1);
      const barrierMaterial = new THREE.MeshLambertMaterial({
        color: 0xff4444,
      });

      // Inner barriers
      for (let i = 0; i < 32; i++) {
        const angle = (i / 32) * Math.PI * 2;
        const barrier = new THREE.Mesh(barrierGeometry, barrierMaterial);
        barrier.position.x = Math.cos(angle) * 14;
        barrier.position.z = Math.sin(angle) * 14;
        barrier.position.y = 1;
        barrier.castShadow = true;
        this.scene.add(barrier);
      }

      // Outer barriers
      for (let i = 0; i < 48; i++) {
        const angle = (i / 48) * Math.PI * 2;
        const barrier = new THREE.Mesh(barrierGeometry, barrierMaterial);
        barrier.position.x = Math.cos(angle) * 26;
        barrier.position.z = Math.sin(angle) * 26;
        barrier.position.y = 1;
        barrier.castShadow = true;
        this.scene.add(barrier);
      }

      // ²³ Start/finish line
      const lineGeometry = new THREE.PlaneGeometry(2, 10);
      const lineMaterial = new THREE.MeshLambertMaterial({
        color: 0xffffff,
        transparent: true,
        opacity: 0.8,
      });
      const startLine = new THREE.Mesh(lineGeometry, lineMaterial);
      startLine.rotation.x = -Math.PI / 2;
      startLine.position.set(20, 0.01, 0);
      this.scene.add(startLine);
    }

    // ²⁴ Create player car
    createCar() {
      const THREE = this.three;

      // Car body
      const carGeometry = new THREE.BoxGeometry(2, 0.8, 4);
      const carColor = this.args.model.carConfig?.color || '#ff6b6b';
      const carMaterial = new THREE.MeshLambertMaterial({ color: carColor });
      this.car = new THREE.Mesh(carGeometry, carMaterial);
      this.car.position.set(20, 0.5, 0);
      this.car.castShadow = true;
      this.scene.add(this.car);

      // Car wheels
      const wheelGeometry = new THREE.CylinderGeometry(0.4, 0.4, 0.3, 16);
      const wheelMaterial = new THREE.MeshLambertMaterial({ color: 0x222222 });

      const wheels = [];
      const wheelPositions = [
        { x: -0.7, y: -0.2, z: 1.3 },
        { x: 0.7, y: -0.2, z: 1.3 },
        { x: -0.7, y: -0.2, z: -1.3 },
        { x: 0.7, y: -0.2, z: -1.3 },
      ];

      wheelPositions.forEach((pos) => {
        const wheel = new THREE.Mesh(wheelGeometry, wheelMaterial);
        wheel.rotation.z = Math.PI / 2;
        wheel.position.set(pos.x, pos.y, pos.z);
        wheel.castShadow = true;
        this.car.add(wheel);
        wheels.push(wheel);
      });

      // Set initial car position
      this.carPosition = { x: 20, y: 0.5, z: 0 };
    }

    // ²⁵ Setup keyboard controls
    setupControls() {
      const handleKeyDown = (event: KeyboardEvent) => {
        switch (event.code) {
          case 'ArrowUp':
          case 'KeyW':
            this.keys.forward = true;
            break;
          case 'ArrowDown':
          case 'KeyS':
            this.keys.backward = true;
            break;
          case 'ArrowLeft':
          case 'KeyA':
            this.keys.left = true;
            break;
          case 'ArrowRight':
          case 'KeyD':
            this.keys.right = true;
            break;
          case 'ShiftLeft':
          case 'ShiftRight':
            this.keys.brake = true;
            event.preventDefault();
            break;
        }
      };

      const handleKeyUp = (event: KeyboardEvent) => {
        switch (event.code) {
          case 'ArrowUp':
          case 'KeyW':
            this.keys.forward = false;
            break;
          case 'ArrowDown':
          case 'KeyS':
            this.keys.backward = false;
            break;
          case 'ArrowLeft':
          case 'KeyA':
            this.keys.left = false;
            break;
          case 'ArrowRight':
          case 'KeyD':
            this.keys.right = false;
            break;
          case 'ShiftLeft':
          case 'ShiftRight':
            this.keys.brake = false;
            break;
        }
      };

      document.addEventListener('keydown', handleKeyDown);
      document.addEventListener('keyup', handleKeyUp);
    }

    // ²⁶ Update car physics
    updateCarPhysics() {
      const baseAcceleration = this.args.model.carConfig?.acceleration || 75;
      const baseMaxSpeed = this.args.model.carConfig?.speed || 85;
      const baseHandling = this.args.model.carConfig?.handling || 85;

      this.acceleration = (baseAcceleration / 100) * 0.1;
      this.maxSpeed = (baseMaxSpeed / 100) * 3;
      this.turnSpeed = (baseHandling / 100) * 0.05;

      // Forward/backward movement
      if (this.keys.forward) {
        this.carSpeed = Math.min(
          this.carSpeed + this.acceleration,
          this.maxSpeed,
        );
      } else if (this.keys.backward) {
        this.carSpeed = Math.max(
          this.carSpeed - this.acceleration * 0.7,
          -this.maxSpeed * 0.5,
        );
      } else {
        this.carSpeed *= this.friction;
      }

      // Braking
      if (this.keys.brake) {
        this.carSpeed *= 0.9;
      }

      // Turning (only when moving)
      if (Math.abs(this.carSpeed) > 0.01) {
        if (this.keys.left) {
          this.carRotation.y +=
            (this.turnSpeed * Math.abs(this.carSpeed)) / this.maxSpeed;
        }
        if (this.keys.right) {
          this.carRotation.y -=
            (this.turnSpeed * Math.abs(this.carSpeed)) / this.maxSpeed;
        }
      }

      // Update velocity based on rotation and speed
      this.carVelocity.x = Math.sin(this.carRotation.y) * this.carSpeed;
      this.carVelocity.z = Math.cos(this.carRotation.y) * this.carSpeed;

      // Update position
      this.carPosition.x += this.carVelocity.x;
      this.carPosition.z += this.carVelocity.z;

      // ²⁷ Track collision detection (keep car on track)
      const distanceFromCenter = Math.sqrt(
        this.carPosition.x * this.carPosition.x +
          this.carPosition.z * this.carPosition.z,
      );

      if (distanceFromCenter > 24 || distanceFromCenter < 16) {
        // Bounce back to track
        this.carPosition.x -= this.carVelocity.x * 2;
        this.carPosition.z -= this.carVelocity.z * 2;
        this.carSpeed *= -0.3; // Reverse and slow down
      }

      // Update car mesh position and rotation
      if (this.car) {
        this.car.position.set(
          this.carPosition.x,
          this.carPosition.y,
          this.carPosition.z,
        );
        this.car.rotation.y = this.carRotation.y;
      }

      // Update speed display
      this.currentSpeed = Math.abs(this.carSpeed * 50); // Convert to km/h scale
    }

    // ²⁸ Update camera to follow car (Mario Kart style)
    updateCamera() {
      if (!this.camera || !this.car) return;

      // Camera position behind car (more behind)
      const cameraDistance = 12;
      const cameraHeight = 5;

      const cameraX =
        this.carPosition.x - Math.sin(this.carRotation.y) * cameraDistance;
      const cameraZ =
        this.carPosition.z - Math.cos(this.carRotation.y) * cameraDistance;

      this.camera.position.x = cameraX;
      this.camera.position.y = this.carPosition.y + cameraHeight;
      this.camera.position.z = cameraZ;

      // Look at car
      this.camera.lookAt(
        this.carPosition.x,
        this.carPosition.y + 1,
        this.carPosition.z,
      );
    }

    // ²⁹ Check lap completion
    checkLapCompletion() {
      // Simple lap detection: check if car crosses start line
      const distanceFromStart = Math.sqrt(
        Math.pow(this.carPosition.x - 20, 2) +
          Math.pow(this.carPosition.z - 0, 2),
      );

      if (distanceFromStart < 3 && this.lapTime > 5) {
        // Minimum 5 seconds per lap
        this.currentLap++;

        if (this.bestLapTime === 0 || this.lapTime < this.bestLapTime) {
          this.bestLapTime = this.lapTime;
        }

        this.lapTime = 0;
      }
    }

    // ³⁰ Main game loop
    startGameLoop() {
      const gameLoop = () => {
        if (!this.renderer || !this.scene || !this.camera) return;

        // Update game time
        this.gameTime += 1 / 60; // Assuming 60 FPS
        this.lapTime += 1 / 60;

        // Update physics
        this.updateCarPhysics();

        // Update camera
        this.updateCamera();

        // Check lap completion
        this.checkLapCompletion();

        // Render scene
        this.renderer.render(this.scene, this.camera);

        // Continue loop
        requestAnimationFrame(gameLoop);
      };

      gameLoop();
    }

    // ³¹ Handle window resize
    @action
    handleResize() {
      if (!this.camera || !this.renderer) return;

      const canvas = this.renderer.domElement;
      this.camera.aspect = canvas.clientWidth / canvas.clientHeight;
      this.camera.updateProjectionMatrix();
      this.renderer.setSize(canvas.clientWidth, canvas.clientHeight);
    }

    @action // ³² Start race with map
    startRace() {
      this.resetGame();
      this.args.model.isGameActive = true;

      // ³⁵ Open race map in side panel if linked
      if (this.args.context?.actions?.viewCard && this.args.model.raceMap) {
        this.args.context.actions.viewCard(
          this.args.model.raceMap,
          'isolated',
          {
            openCardInRightMostStack: true,
          },
        );
      }
    }

    @action // ³² Reset game
    resetGame() {
      this.carPosition = { x: 20, y: 0.5, z: 0 };
      this.carRotation = { x: 0, y: 0, z: 0 };
      this.carVelocity = { x: 0, y: 0, z: 0 };
      this.carSpeed = 0;
      this.currentSpeed = 0;
      this.currentLap = 1;
      this.lapTime = 0;
      this.gameTime = 0;
      this.bestLapTime = 0;

      if (this.car) {
        this.car.position.set(20, 0.5, 0);
        this.car.rotation.set(0, 0, 0);
      }
    }

    <template>
      <div class='stage'>
        <div class='racing-game-mat'>
          <header class='game-header'>
            <h1>{{if @model.gameName @model.gameName 'Racing Game'}}</h1>
            {{#if @model.cardDescription}}
              <p class='game-description'>{{@model.cardDescription}}</p>
            {{/if}}
          </header>

          <!-- ³³ Game canvas and HUD -->
          <div class='game-container'>
            <canvas
              class='game-canvas'
              width='800'
              height='600'
              {{ThreeJsModifier this}}
              {{on 'resize' this.handleResize}}
            ></canvas>

            <!-- ³⁴ HUD overlay -->
            <div class='hud-overlay'>
              <!-- Speed and lap info -->
              <div class='hud-top-left'>
                <div class='speed-display'>
                  <span class='speed-value'>{{this.currentSpeed}}</span>
                  <span class='speed-unit'>km/h</span>
                </div>
                <div class='lap-display'>
                  <span class='lap-label'>Lap:</span>
                  <span class='lap-value'>{{this.currentLap}}</span>
                </div>
              </div>

              <!-- Lap times -->
              <div class='hud-top-right'>
                <div class='time-display'>
                  <div class='current-time'>
                    <span class='time-label'>Current:</span>
                    <span class='time-value'>{{if
                        this.lapTime
                        (concat (Math.round (multiply this.lapTime 100)) 's')
                        '--'
                      }}</span>
                  </div>
                  {{#if this.bestLapTime}}
                    <div class='best-time'>
                      <span class='time-label'>Best:</span>
                      <span class='time-value'>{{this.bestLapTime}}s</span>
                    </div>
                  {{/if}}
                </div>
              </div>

              <!-- Controls info -->
              <div class='hud-bottom'>
                <div class='controls-help'>
                  <span class='control'>WASD / Arrow Keys: Drive</span>
                  <span class='control'>Shift: Brake</span>
                  <Button class='reset-btn' {{on 'click' this.resetGame}}>Reset
                    Position</Button>
                </div>
              </div>
            </div>
          </div>

          <!-- ³⁵ Race controls and map -->
          <section class='race-controls-section'>
            <div class='controls-grid'>
              {{#if @model.isGameActive}}
                <Button
                  class='control-button reset-button'
                  {{on 'click' this.resetGame}}
                >
                  <svg
                    class='button-icon'
                    viewBox='0 0 24 24'
                    fill='none'
                    stroke='currentColor'
                    stroke-width='2'
                  >
                    <polyline points='23 4 23 10 17 10' />
                    <path d='M20.49 15a9 9 0 1 1-2.12-9.36L23 10' />
                  </svg>
                  Reset Race
                </Button>
              {{else}}
                <Button
                  class='control-button start-race-button'
                  {{on 'click' this.startRace}}
                >
                  <svg
                    class='button-icon'
                    viewBox='0 0 24 24'
                    fill='currentColor'
                  >
                    <polygon points='5,3 19,12 5,21' />
                  </svg>
                  Start Race{{#if @model.raceMap}} & Open Map{{/if}}
                </Button>
              {{/if}}

              {{#if @model.raceMap}}
                <div class='map-link'>
                  <span class='map-info'>📍 Race map will open in side panel</span>
                </div>
              {{/if}}
            </div>
          </section>

          <!-- ³⁶ Car configuration -->
          {{#if @model.carConfig}}
            <section class='car-section'>
              <h3>Car Configuration</h3>
              <@fields.carConfig />
            </section>
          {{/if}}

          <!-- ³⁷ Linked race map -->
          {{#if @model.raceMap}}
            <section class='map-section'>
              <h3>Race Map</h3>
              <@fields.raceMap @format='embedded' />
            </section>
          {{/if}}

        </div>
      </div>

      <style scoped>
        /* ³⁷ Racing game styles */
        .stage {
          width: 100%;
          height: 100%;
          display: flex;
          justify-content: center;
          padding: 1rem;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          font-family:
            'Inter',
            -apple-system,
            sans-serif;
        }

        .racing-game-mat {
          max-width: 70rem;
          width: 100%;
          overflow-y: auto;
          max-height: 100%;
        }

        .game-header {
          text-align: center;
          margin-bottom: 1.5rem;
        }

        .game-header h1 {
          font-size: 2.5rem;
          font-weight: 800;
          color: white;
          margin-bottom: 0.5rem;
          text-shadow: 0 2px 4px rgba(0, 0, 0, 0.3);
        }

        .game-description {
          color: rgba(255, 255, 255, 0.9);
          font-size: 1.125rem;
          line-height: 1.5;
        }

        .game-container {
          position: relative;
          background: black;
          border-radius: 1rem;
          overflow: hidden;
          box-shadow: 0 20px 40px rgba(0, 0, 0, 0.3);
          margin-bottom: 2rem;
        }

        .game-canvas {
          width: 100%;
          height: 600px;
          display: block;
          background: #87ceeb;
        }

        /* ³⁸ HUD styles */
        .hud-overlay {
          position: absolute;
          top: 0;
          left: 0;
          right: 0;
          bottom: 0;
          pointer-events: none;
          z-index: 10;
        }

        .hud-top-left {
          position: absolute;
          top: 1rem;
          left: 1rem;
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
        }

        .speed-display {
          background: rgba(0, 0, 0, 0.8);
          padding: 0.75rem 1rem;
          border-radius: 0.5rem;
          text-align: center;
          border: 2px solid #00ff00;
        }

        .speed-value {
          display: block;
          font-size: 2rem;
          font-weight: 800;
          color: #00ff00;
          line-height: 1;
          font-family: 'SF Mono', Monaco, monospace;
        }

        .speed-unit {
          font-size: 0.875rem;
          color: white;
          font-weight: 600;
        }

        .lap-display {
          background: rgba(0, 0, 0, 0.8);
          padding: 0.5rem 1rem;
          border-radius: 0.5rem;
          text-align: center;
          border: 2px solid #ffaa00;
        }

        .lap-label {
          color: white;
          font-size: 0.875rem;
          margin-right: 0.5rem;
        }

        .lap-value {
          color: #ffaa00;
          font-size: 1.5rem;
          font-weight: 800;
          font-family: 'SF Mono', Monaco, monospace;
        }

        .hud-top-right {
          position: absolute;
          top: 1rem;
          right: 1rem;
        }

        .time-display {
          background: rgba(0, 0, 0, 0.8);
          padding: 0.75rem 1rem;
          border-radius: 0.5rem;
          border: 2px solid #0088ff;
          min-width: 150px;
        }

        .current-time,
        .best-time {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 0.25rem;
        }

        .best-time {
          margin-bottom: 0;
        }

        .time-label {
          color: white;
          font-size: 0.875rem;
          font-weight: 500;
        }

        .time-value {
          color: #0088ff;
          font-family: 'SF Mono', Monaco, monospace;
          font-weight: 600;
        }

        .hud-bottom {
          position: absolute;
          bottom: 1rem;
          left: 1rem;
          right: 1rem;
          display: flex;
          justify-content: center;
        }

        .controls-help {
          background: rgba(0, 0, 0, 0.8);
          padding: 0.75rem 1.5rem;
          border-radius: 0.5rem;
          display: flex;
          align-items: center;
          gap: 1.5rem;
          border: 2px solid rgba(255, 255, 255, 0.3);
        }

        .control {
          color: white;
          font-size: 0.875rem;
          font-weight: 500;
        }

        .reset-btn {
          background: #ff4444;
          color: white;
          border: none;
          padding: 0.5rem 1rem;
          border-radius: 0.375rem;
          font-size: 0.875rem;
          font-weight: 600;
          cursor: pointer;
          pointer-events: auto;
          transition: all 0.2s ease;
        }

        .reset-btn:hover {
          background: #ff6666;
          transform: translateY(-1px);
        }

        /* ³⁹ Race controls section */
        .race-controls-section {
          background: rgba(255, 255, 255, 0.95);
          backdrop-filter: blur(10px);
          border-radius: 1rem;
          padding: 1.5rem;
          margin-bottom: 1.5rem;
          box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
          border: 1px solid rgba(255, 255, 255, 0.2);
        }

        .controls-grid {
          display: flex;
          flex-direction: column;
          gap: 1rem;
          align-items: center;
        }

        .control-button {
          padding: 1rem 2rem;
          border-radius: 0.75rem;
          font-size: 1rem;
          font-weight: 700;
          display: flex;
          align-items: center;
          gap: 0.75rem;
          cursor: pointer;
          transition: all 0.3s ease;
          border: none;
          min-width: 200px;
          justify-content: center;
        }

        .start-race-button {
          background: linear-gradient(135deg, #10b981 0%, #059669 100%);
          color: white;
          box-shadow: 0 4px 15px rgba(16, 185, 129, 0.4);
        }

        .start-race-button:hover {
          transform: translateY(-2px);
          box-shadow: 0 8px 25px rgba(16, 185, 129, 0.5);
        }

        .reset-button {
          background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%);
          color: white;
          box-shadow: 0 4px 15px rgba(239, 68, 68, 0.4);
        }

        .reset-button:hover {
          transform: translateY(-2px);
          box-shadow: 0 8px 25px rgba(239, 68, 68, 0.5);
        }

        .button-icon {
          width: 1.25rem;
          height: 1.25rem;
        }

        .map-link {
          text-align: center;
        }

        .map-info {
          font-size: 0.875rem;
          color: rgba(255, 255, 255, 0.8);
          background: rgba(59, 130, 246, 0.2);
          padding: 0.5rem 1rem;
          border-radius: 0.5rem;
          display: inline-block;
        }

        /* ⁴⁰ Configuration sections */
        .car-section,
        .map-section {
          background: white;
          border-radius: 1rem;
          padding: 1.5rem;
          margin-bottom: 1.5rem;
          box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
        }

        .car-section h3,
        .map-section h3 {
          font-size: 1.25rem;
          font-weight: 700;
          color: #111827;
          margin-bottom: 1rem;
        }

        /* ⁴⁰ Responsive design */
        @media (max-width: 768px) {
          .stage {
            padding: 0.5rem;
          }

          .game-header h1 {
            font-size: 2rem;
          }

          .game-canvas {
            height: 400px;
          }

          .controls-help {
            flex-direction: column;
            gap: 0.5rem;
            text-align: center;
          }

          .hud-top-left,
          .hud-top-right {
            position: static;
            margin-bottom: 1rem;
          }

          .hud-bottom {
            position: static;
            margin-top: 1rem;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    // ⁴¹ Embedded format
    <template>
      <div class='racing-game-card'>
        <header>
          <h3>{{if @model.gameName @model.gameName 'Racing Game'}}</h3>
          {{#if @model.cardDescription}}
            <p class='card-description'>{{@model.cardDescription}}</p>
          {{/if}}
        </header>

        <div class='game-preview'>
          <svg
            class='racing-icon'
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2'
          >
            <path
              d='M18 10h-1.26A8 8 0 1 0 9 20h9a2 2 0 0 0 2-2v-6a2 2 0 0 0-2-2z'
            />
            <circle cx='9' cy='17' r='2' />
            <circle cx='18' cy='17' r='2' />
          </svg>
          <div class='preview-text'>
            {{#if @model.isGameActive}}
              <span class='status active'>Game Active</span>
              <span class='stats'>Speed: {{this.currentSpeed}} km/h</span>
            {{else}}
              <span class='status inactive'>Ready to Race</span>
            {{/if}}
          </div>
        </div>
      </div>

      <style scoped>
        .racing-game-card {
          border: 1px solid #e5e7eb;
          border-radius: 0.75rem;
          padding: 1.5rem;
          background: white;
        }

        .racing-game-card header h3 {
          font-size: 1.25rem;
          font-weight: 700;
          color: #111827;
          margin-bottom: 0.5rem;
        }

        .card-description {
          font-size: 0.875rem;
          color: #6b7280;
          line-height: 1.5;
          margin-bottom: 1rem;
        }

        .game-preview {
          display: flex;
          align-items: center;
          gap: 1rem;
          padding: 1rem;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          border-radius: 0.5rem;
          color: white;
        }

        .racing-icon {
          width: 2.5rem;
          height: 2.5rem;
          flex-shrink: 0;
        }

        .preview-text {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
        }

        .status {
          font-weight: 600;
          font-size: 0.875rem;
        }

        .status.active {
          color: #00ff00;
        }

        .status.inactive {
          color: #ffaa00;
        }

        .stats {
          font-size: 0.75rem;
          opacity: 0.9;
          font-family: 'SF Mono', Monaco, monospace;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    // ⁴² Fitted format
    <template>
      <div class='fitted-container'>
        <!-- Badge format -->
        <div class='badge-format'>
          <svg
            class='badge-icon'
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2'
          >
            <path
              d='M18 10h-1.26A8 8 0 1 0 9 20h9a2 2 0 0 0 2-2v-6a2 2 0 0 0-2-2z'
            />
            <circle cx='9' cy='17' r='2' />
            <circle cx='18' cy='17' r='2' />
          </svg>
          <div class='badge-text'>
            <span class='badge-title'>{{if
                @model.gameName
                @model.gameName
                'Racing'
              }}</span>
            {{#if @model.isGameActive}}
              <span class='badge-status'>Active</span>
            {{else}}
              <span class='badge-status'>Ready</span>
            {{/if}}
          </div>
        </div>

        <!-- Strip format -->
        <div class='strip-format'>
          <svg
            class='strip-icon'
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2'
          >
            <path
              d='M18 10h-1.26A8 8 0 1 0 9 20h9a2 2 0 0 0 2-2v-6a2 2 0 0 0-2-2z'
            />
            <circle cx='9' cy='17' r='2' />
            <circle cx='18' cy='17' r='2' />
          </svg>
          <div class='strip-text'>
            <span class='strip-title'>{{if
                @model.gameName
                @model.gameName
                'Racing Game'
              }}</span>
            <span class='strip-meta'>3D Mario Kart-style racing • Behind-car
              camera</span>
          </div>
        </div>

        <!-- Tile format -->
        <div class='tile-format'>
          <div class='tile-header'>
            <svg
              class='tile-icon'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            >
              <path
                d='M18 10h-1.26A8 8 0 1 0 9 20h9a2 2 0 0 0 2-2v-6a2 2 0 0 0-2-2z'
              />
              <circle cx='9' cy='17' r='2' />
              <circle cx='18' cy='17' r='2' />
            </svg>
            <h4 class='tile-title'>{{if
                @model.gameName
                @model.gameName
                'Racing Game'
              }}</h4>
          </div>
          <div class='tile-preview'>
            <div class='preview-track'>
              <div class='track-curve'></div>
              <div class='mini-car'></div>
            </div>
          </div>
          <div class='tile-stats'>
            {{#if @model.isGameActive}}
              <span class='tile-stat'>{{this.currentSpeed}} km/h</span>
              <span class='tile-stat'>Lap {{this.currentLap}}</span>
            {{else}}
              <span class='tile-stat'>Ready to Race</span>
            {{/if}}
          </div>
        </div>

        <!-- Card format -->
        <div class='card-format'>
          <div class='card-header'>
            <div class='card-title-section'>
              <svg
                class='card-icon'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              >
                <path
                  d='M18 10h-1.26A8 8 0 1 0 9 20h9a2 2 0 0 0 2-2v-6a2 2 0 0 0-2-2z'
                />
                <circle cx='9' cy='17' r='2' />
                <circle cx='18' cy='17' r='2' />
              </svg>
              <div>
                <h4 class='card-title'>{{if
                    @model.gameName
                    @model.gameName
                    'Racing Game'
                  }}</h4>
                {{#if @model.cardDescription}}
                  <p class='card-description'>{{@model.cardDescription}}</p>
                {{/if}}
              </div>
            </div>
            {{#if @model.isGameActive}}
              <div class='card-stats'>
                <span class='stat-number'>{{this.currentSpeed}}</span>
                <span class='stat-label'>km/h</span>
              </div>
            {{/if}}
          </div>

          <div class='card-preview'>
            <div class='track-visualization'>
              <div class='track-oval'>
                <div class='car-indicator'></div>
                <div class='start-line'></div>
              </div>
            </div>
            {{#if @model.isGameActive}}
              <div class='race-info'>
                <div class='info-item'>
                  <span class='label'>Lap:</span>
                  <span class='value'>{{this.currentLap}}</span>
                </div>
                <div class='info-item'>
                  <span class='label'>Best:</span>
                  <span class='value'>{{if
                      this.bestLapTime
                      (concat this.bestLapTime 's')
                      '--'
                    }}</span>
                </div>
              </div>
            {{/if}}
          </div>
        </div>
      </div>

      <style scoped>
        /* Standard fitted format container setup */
        .fitted-container {
          container-type: size;
          width: 100%;
          height: 100%;
          font-family:
            'Inter',
            -apple-system,
            sans-serif;
        }

        .badge-format,
        .strip-format,
        .tile-format,
        .card-format {
          display: none;
          width: 100%;
          height: 100%;
          padding: clamp(0.1875rem, 2%, 0.625rem);
          box-sizing: border-box;
        }

        /* Badge format */
        @container (max-width: 150px) and (max-height: 169px) {
          .badge-format {
            display: flex;
            align-items: center;
          }
        }

        .badge-format {
          gap: 0.5rem;
        }

        .badge-icon {
          width: clamp(1rem, 5%, 1.5rem);
          height: clamp(1rem, 5%, 1.5rem);
          color: #667eea;
          flex-shrink: 0;
        }

        .badge-text {
          display: flex;
          flex-direction: column;
          min-width: 0;
        }

        .badge-title {
          font-size: clamp(0.625rem, 4%, 0.75rem);
          font-weight: 600;
          color: #111827;
          line-height: 1.2;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .badge-status {
          font-size: clamp(0.5rem, 3%, 0.625rem);
          color: #6b7280;
          font-weight: 500;
        }

        /* Strip format */
        @container (min-width: 151px) and (max-height: 169px) {
          .strip-format {
            display: flex;
            align-items: center;
          }
        }

        .strip-format {
          gap: 0.75rem;
        }

        .strip-icon {
          width: clamp(1.25rem, 6%, 2rem);
          height: clamp(1.25rem, 6%, 2rem);
          color: #667eea;
          flex-shrink: 0;
        }

        .strip-text {
          display: flex;
          flex-direction: column;
          min-width: 0;
          flex: 1;
        }

        .strip-title {
          font-size: clamp(0.75rem, 4%, 0.875rem);
          font-weight: 600;
          color: #111827;
          line-height: 1.2;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .strip-meta {
          font-size: clamp(0.625rem, 3%, 0.75rem);
          color: #6b7280;
          font-weight: 500;
          line-height: 1.2;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        /* Tile format */
        @container (max-width: 399px) and (min-height: 170px) {
          .tile-format {
            display: flex;
            flex-direction: column;
          }
        }

        .tile-header {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          margin-bottom: 0.75rem;
        }

        .tile-icon {
          width: 1.25rem;
          height: 1.25rem;
          color: #667eea;
          flex-shrink: 0;
        }

        .tile-title {
          font-size: 0.875rem;
          font-weight: 600;
          color: #111827;
          line-height: 1.2;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          flex: 1;
        }

        .tile-preview {
          flex: 1;
          display: flex;
          align-items: center;
          justify-content: center;
          margin-bottom: 0.75rem;
        }

        .preview-track {
          position: relative;
          width: 80px;
          height: 80px;
          border: 3px solid #333;
          border-radius: 50%;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }

        .track-curve {
          position: absolute;
          inset: 8px;
          border: 2px solid #333;
          border-radius: 50%;
        }

        .mini-car {
          position: absolute;
          top: 10px;
          right: 10px;
          width: 8px;
          height: 12px;
          background: #ff6b6b;
          border-radius: 2px;
          transform: rotate(45deg);
        }

        .tile-stats {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-top: auto;
          font-size: 0.75rem;
          font-weight: 600;
        }

        .tile-stat {
          color: #111827;
        }

        /* Card format */
        @container (min-width: 400px) and (min-height: 170px) {
          .card-format {
            display: flex;
            flex-direction: column;
          }
        }

        .card-header {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          margin-bottom: 1rem;
        }

        .card-title-section {
          display: flex;
          align-items: flex-start;
          gap: 0.75rem;
          flex: 1;
          min-width: 0;
        }

        .card-icon {
          width: 1.5rem;
          height: 1.5rem;
          color: #667eea;
          flex-shrink: 0;
          margin-top: 0.125rem;
        }

        .card-title {
          font-size: 1rem;
          font-weight: 600;
          color: #111827;
          line-height: 1.3;
          margin-bottom: 0.25rem;
        }

        .card-description {
          font-size: 0.75rem;
          color: #6b7280;
          line-height: 1.4;
          overflow: hidden;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }

        .card-stats {
          display: flex;
          flex-direction: column;
          align-items: center;
          text-align: center;
          margin-left: 1rem;
        }

        .stat-number {
          font-size: 1.25rem;
          font-weight: 700;
          color: #667eea;
          line-height: 1;
        }

        .stat-label {
          font-size: 0.625rem;
          color: #6b7280;
          font-weight: 500;
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }

        .card-preview {
          flex: 1;
          display: flex;
          gap: 1rem;
        }

        .track-visualization {
          flex: 1;
          display: flex;
          align-items: center;
          justify-content: center;
        }

        .track-oval {
          position: relative;
          width: 120px;
          height: 120px;
          border: 4px solid #333;
          border-radius: 50%;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }

        .track-oval::before {
          content: '';
          position: absolute;
          inset: 12px;
          border: 3px solid #333;
          border-radius: 50%;
        }

        .car-indicator {
          position: absolute;
          top: 15px;
          right: 15px;
          width: 12px;
          height: 16px;
          background: #ff6b6b;
          border-radius: 3px;
          transform: rotate(45deg);
          box-shadow: 0 2px 4px rgba(0, 0, 0, 0.3);
        }

        .start-line {
          position: absolute;
          top: 50%;
          right: -2px;
          width: 8px;
          height: 20px;
          background: white;
          transform: translateY(-50%);
        }

        .race-info {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
          justify-content: center;
        }

        .info-item {
          display: flex;
          justify-content: space-between;
          align-items: center;
          font-size: 0.875rem;
        }

        .info-item .label {
          color: #6b7280;
          font-weight: 500;
        }

        .info-item .value {
          color: #111827;
          font-weight: 600;
          font-family: 'SF Mono', Monaco, monospace;
        }

        /* Compact card layout */
        @container (min-width: 400px) and (height: 170px) {
          .card-format {
            flex-direction: row;
            gap: 1rem;
          }

          .card-format > * {
            display: flex;
            flex-direction: column;
          }

          .card-format > *:first-child {
            flex: 1.618;
          }

          .card-format > *:last-child {
            flex: 1;
          }
        }
      </style>
    </template>
  };
}
