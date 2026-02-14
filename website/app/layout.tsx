import type { Metadata } from "next";
import { Header } from "./components/header";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "Broker CLI — Give Your AI Agent a Brokerage Account",
    template: "%s | Broker CLI",
  },
  description:
    "Open-source CLI that turns any brokerage into shell commands your AI agent already understands. Interactive Brokers and E*Trade. Portfolio, options, exposure, and more.",
  metadataBase: new URL("https://brokercli.com"),
  keywords: [
    "broker cli",
    "ai trading",
    "algorithmic trading",
    "interactive brokers cli",
    "etrade cli",
    "ai agent trading",
    "terminal trading",
  ],
  openGraph: {
    title: "Broker CLI — Give Your AI Agent a Brokerage Account",
    description:
      "Open-source CLI that turns any brokerage into shell commands your AI agent already understands.",
    url: "https://brokercli.com",
    siteName: "Broker CLI",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Broker CLI — Give Your AI Agent a Brokerage Account",
    description:
      "Open-source CLI that turns any brokerage into shell commands your AI agent already understands.",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="min-h-screen">
        <Header />
        {children}
      </body>
    </html>
  );
}
