import type { NextConfig } from "next";

const basePath = process.env.NEXT_PUBLIC_BASE_PATH || (process.env.GITHUB_PAGES ? "/frieds-hotwm" : "");

const nextConfig: NextConfig = {
  output: "export",
  basePath: basePath,
  images: { unoptimized: true },
  trailingSlash: true,
};

export default nextConfig;
