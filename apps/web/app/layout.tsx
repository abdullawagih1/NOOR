import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Noor — Clinical Intelligence OS",
  description:
    "Evidence-grounded clinical decision support. Sprint 0 foundation build.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
