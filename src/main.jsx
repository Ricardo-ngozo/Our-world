import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App.jsx';
import './app.css';
import 'leaflet/dist/leaflet.css';

if ('serviceWorker' in navigator && import.meta.env.PROD) navigator.serviceWorker.register('/sw.js').catch(()=>{});
createRoot(document.getElementById('root')).render(<React.StrictMode><App/></React.StrictMode>);

