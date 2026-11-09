import Nav from './components/Nav';
import Hero from './components/Hero';
import Platform from './components/Platform';
import Audience from './components/Audience';
import HowItWorks from './components/HowItWorks';
import Contribute from './components/Contribute';
import AccessForm from './components/AccessForm';
import Footer from './components/Footer';

/** Single-page layout. Section order follows the brief. */
export default function App() {
  return (
    <>
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-[60] focus:rounded-md focus:bg-accent focus:px-4 focus:py-2 focus:text-navy"
      >
        Skip to content
      </a>
      <Nav />
      <main id="main">
        <Hero />
        <Platform />
        <Audience />
        <HowItWorks />
        <Contribute />
        <AccessForm />
      </main>
      <Footer />
    </>
  );
}
