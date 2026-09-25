# NotchBrow

A small browser that opens from your Mac’s notch. Click it, look something up, then tuck it away when you’re done. Your tabs stay open.

No notch? It adds a small black one at the top of the screen. It works on external displays too.

Built with Swift, AppKit, and the WebKit that comes with macOS. The app is about 1.5 MB.

## Install

[Download NotchBrow](https://github.com/guyonlocalhost/NotchBrow/releases/latest/download/NotchBrow-universal.zip), unzip it, and drag **NotchBrow.app** into **Applications**.

You’ll need macOS 13 or later. The same download works on Intel and Apple silicon.

The app isn’t Apple-notarized yet, so macOS may require approval before opening it for the first time.

## Using it

Click the notch or press **Control–Option–Space** to open it. Click outside the browser to tuck it away, or pin it if you want it to stay open.

If you’d rather open it by hovering, right-click the notch and choose **Open notch with → Hover**. You can change this back to Click whenever you want.

There are tabs, bookmarks, downloads, find in page, and page zoom. Type a URL in the address bar, or type a search and it’ll use DuckDuckGo. The full-screen button opens a normal macOS full-screen window. Closing that window leaves the notch available.

A few useful shortcuts:

| Shortcut | What it does |
| --- | --- |
| Control–Option–Space | Open or tuck away |
| Command–L | Focus the address bar |
| Command–T / Command–W | Open or close a tab |
| Command–D | Save or unsave a page |
| Command–F | Find on the page |
| Control–Command–F | Enter or leave full screen |

Chrome extensions aren’t supported. Also, the simulated notch sits over the menu bar; macOS won’t move long app menus around it. The menu bar icon and keyboard shortcut are there if you need another way in.

## Updates

Open **About NotchBrow** and click **Update NotchBrow**. You can also find it in the browser’s **•••** menu or by right-clicking the notch.

When an update is available, the app checks its signature, installs it, and restarts. Your open tab URLs are restored, but the pages reload.

## Build it

You’ll need the Xcode Command Line Tools with Swift 5.9 or later.

```sh
git clone https://github.com/guyonlocalhost/NotchBrow.git
cd NotchBrow
./Scripts/package_app.sh
./Scripts/run.sh
```

The build puts the app in `build/NotchBrow.app` and includes both Mac architectures. To run the checks:

```sh
./Scripts/test.sh
```

## License

[MIT](LICENSE). Copyright © 2026 [Guy on localhost](https://github.com/guyonlocalhost).

Use it, change it, or ship your own version. Keep the copyright and license notice with it.
