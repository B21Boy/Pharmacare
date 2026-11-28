// Import the functions you need from the SDKs you need
import { initializeApp } from "firebase/app";
import { getAnalytics } from "firebase/analytics";
// TODO: Add SDKs for Firebase products that you want to use
// https://firebase.google.com/docs/web/setup#available-libraries

// Your web app's Firebase configuration
// For Firebase JS SDK v7.20.0 and later, measurementId is optional
const firebaseConfig = {
  apiKey: "AIzaSyCxmYy_qeXdHLz5LPJeAtJkV0L5vacRIYM",
  authDomain: "pharmacare-a43c3.firebaseapp.com",
  projectId: "pharmacare-a43c3",
  storageBucket: "pharmacare-a43c3.firebasestorage.app",
  messagingSenderId: "1022591716436",
  appId: "1:1022591716436:web:d25afdb269ae378c7331c1",
  measurementId: "G-XT99BGN52G"
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);
const analytics = getAnalytics(app);