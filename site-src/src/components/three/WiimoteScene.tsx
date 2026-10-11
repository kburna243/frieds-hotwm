"use client";

import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { Float, RoundedBox, Sparkles, ContactShadows } from "@react-three/drei";
import { useRef, useMemo } from "react";
import * as THREE from "three";
import { ledsFromHealth, useHaptics } from "@/lib/store";

const CREAM = "#f4f1e9";
const DARK = "#1a2630";
const MINT = "#3ddc84";
const GOLD = "#ffc857";
const CORAL = "#ff4b3a";

function Button({
  position,
  radius = 0.12,
  height = 0.06,
  color = DARK,
}: {
  position: [number, number, number];
  radius?: number;
  height?: number;
  color?: string;
}) {
  return (
    <mesh position={position} rotation={[Math.PI / 2, 0, 0]}>
      <cylinderGeometry args={[radius, radius, height, 32]} />
      <meshStandardMaterial color={color} roughness={0.5} />
    </mesh>
  );
}

function Leds() {
  const health = useHaptics((s) => s.health);
  const lit = ledsFromHealth(health);
  return (
    <group position={[0, -1.62, 0.4]}>
      {lit.map((on, i) => (
        <mesh key={i} position={[-0.3 + i * 0.2, 0, 0]}>
          <boxGeometry args={[0.11, 0.07, 0.03]} />
          <meshStandardMaterial
            color={on ? MINT : "#2a3a44"}
            emissive={on ? MINT : "#000000"}
            emissiveIntensity={on ? 2.2 : 0}
            toneMapped={false}
          />
        </mesh>
      ))}
    </group>
  );
}

function WiimoteModel() {
  const group = useRef<THREE.Group>(null);
  const flash = useRef<THREE.PointLight>(null);
  const { pointer } = useThree();
  const target = useMemo(() => new THREE.Vector3(), []);

  useFrame((_, dt) => {
    const g = group.current;
    if (!g) return;
    const { rumbleUntil, rumbleStrength } = useHaptics.getState();
    const now = performance.now();
    const rumbling = now < rumbleUntil;

    // follow pointer softly
    const ry = pointer.x * 0.6;
    const rx = -pointer.y * 0.35;
    g.rotation.y = THREE.MathUtils.damp(g.rotation.y, ry, 4, dt);
    g.rotation.x = THREE.MathUtils.damp(g.rotation.x, rx, 4, dt);

    if (rumbling) {
      const a = 0.06 * rumbleStrength;
      target.set(
        (Math.random() - 0.5) * a * 2,
        (Math.random() - 0.5) * a * 2,
        (Math.random() - 0.5) * a,
      );
      g.position.copy(target);
      g.rotation.z = -0.3 + (Math.random() - 0.5) * 0.08 * rumbleStrength;
      if (flash.current) flash.current.intensity = 14 * rumbleStrength;
    } else {
      g.position.lerp(new THREE.Vector3(0, 0, 0), 0.25);
      g.rotation.z = THREE.MathUtils.damp(g.rotation.z, -0.3, 8, dt);
      if (flash.current)
        flash.current.intensity = THREE.MathUtils.damp(flash.current.intensity, 0, 10, dt);
    }
  });

  return (
    <group ref={group} rotation={[0, 0, -0.3]}>
      <pointLight ref={flash} position={[0, 2.3, 0.6]} color={GOLD} intensity={0} distance={5} />

      {/* body */}
      <RoundedBox args={[0.9, 3.7, 0.75]} radius={0.14} smoothness={6}>
        <meshStandardMaterial color={CREAM} roughness={0.35} metalness={0.05} />
      </RoundedBox>

      {/* front face plate (slightly inset) */}
      <mesh position={[0, 0, 0.376]}>
        <planeGeometry args={[0.76, 3.5]} />
        <meshStandardMaterial color="#ece8de" roughness={0.6} />
      </mesh>

      {/* power */}
      <Button position={[-0.26, 1.55, 0.4]} radius={0.06} color={CORAL} />

      {/* d-pad */}
      <group position={[0, 1.12, 0.4]}>
        <mesh>
          <boxGeometry args={[0.44, 0.15, 0.06]} />
          <meshStandardMaterial color={DARK} />
        </mesh>
        <mesh>
          <boxGeometry args={[0.15, 0.44, 0.06]} />
          <meshStandardMaterial color={DARK} />
        </mesh>
      </group>

      {/* A */}
      <Button position={[0, 0.55, 0.4]} radius={0.17} height={0.08} color={DARK} />

      {/* - home + */}
      <Button position={[-0.25, 0.08, 0.4]} radius={0.07} />
      <Button position={[0, 0.08, 0.4]} radius={0.09} color="#243440" />
      <Button position={[0.25, 0.08, 0.4]} radius={0.07} />

      {/* speaker grid */}
      <group position={[0, -0.42, 0.39]}>
        {Array.from({ length: 9 }).map((_, i) => (
          <mesh key={i} position={[((i % 3) - 1) * 0.11, (Math.floor(i / 3) - 1) * 0.11, 0]}>
            <circleGeometry args={[0.03, 12]} />
            <meshStandardMaterial color="#9aa4aa" />
          </mesh>
        ))}
      </group>

      {/* 1 & 2 */}
      <Button position={[0, -0.9, 0.4]} radius={0.11} />
      <Button position={[0, -1.22, 0.4]} radius={0.11} />

      {/* LEDs */}
      <Leds />

      {/* B trigger (back) */}
      <mesh position={[0, 1.0, -0.45]}>
        <boxGeometry args={[0.32, 0.55, 0.22]} />
        <meshStandardMaterial color={DARK} roughness={0.6} />
      </mesh>

      {/* IR window (top) */}
      <mesh position={[0, 1.87, 0]}>
        <boxGeometry args={[0.6, 0.06, 0.45]} />
        <meshStandardMaterial color="#111" roughness={0.1} metalness={0.5} />
      </mesh>
    </group>
  );
}

export default function WiimoteScene() {
  const fire = useHaptics((s) => s.fire);
  return (
    <Canvas
      dpr={[1, 1.75]}
      camera={{ position: [0, 0, 7.5], fov: 32 }}
      gl={{ antialias: true, alpha: true }}
      onPointerDown={() => fire()}
      className="cursor-crosshair"
    >
      <ambientLight intensity={0.6} />
      <directionalLight position={[4, 6, 5]} intensity={2.2} color="#fff6e5" />
      <pointLight position={[-4, -3, 3]} intensity={6} color={MINT} distance={12} />
      <pointLight position={[3, -2, -3]} intensity={4} color={GOLD} distance={12} />
      <Float speed={1.6} rotationIntensity={0.35} floatIntensity={0.9}>
        <WiimoteModel />
      </Float>
      <Sparkles count={60} scale={[8, 6, 4]} size={2.2} speed={0.4} color={MINT} opacity={0.5} />
      <ContactShadows position={[0, -2.6, 0]} opacity={0.45} scale={8} blur={2.5} far={4} color="#000" />
    </Canvas>
  );
}
