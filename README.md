# Job Update — Interview Dashboard

A mobile-friendly interview pipeline dashboard built for Vercel.

## Features

- Interview pipeline metrics and follow-up warnings
- Search and status filters
- Add, edit, and delete records
- Import `.xlsx`, `.xls`, `.csv`, or `.json`
- Export the current tracker to Excel
- Device storage fallback
- Private Vercel Blob persistence
- Password-protected cloud reads and writes

## Privacy

This public repository intentionally contains **no personal interview records, Gmail links, or Excel tracker file**. Import the private Excel tracker only after deployment. Cloud records are stored in a **Private** Vercel Blob store and are served only through the password-protected API route.

Do not commit `.env` files or private spreadsheets.

## Deploy to Vercel

1. In Vercel, choose **Add New → Project** and import this repository.
2. Deploy it. No custom build command is required.
3. In the Vercel project, open **Storage**, create a Blob store, and choose **Private** access.
4. Connect that Blob store to this project.
5. Under **Settings → Environment Variables**, add a strong `ADMIN_PASSWORD`.
6. Redeploy once after connecting storage and adding the password.
7. Open the website, enter the admin password, import the private Excel tracker, then press **Save changes**.

Without Blob, the dashboard still works using browser storage on the current device.

## Local preview

Serve the folder with any static development server. The Vercel API route requires a deployed or locally emulated Vercel environment to use cloud persistence.
