// tinyraven: Firefox memory settings for a 4 GB machine. setup.sh copies this file into
// each Firefox profile; Firefox reads it at every start. Delete a line to get the default back.
// Defaults quoted are Firefox 160's own, read from its files on this machine.

// Fewer content processes: each one costs memory before it shows a page. (default 8)
user_pref("dom.ipc.processCount", 2);
// One process per site, not up to four. Site isolation itself stays on. (default 4)
user_pref("dom.ipc.processCount.webIsolated", 1);
// When memory runs low, unload tabs you have not used for a while; they reload on click. (default false)
user_pref("browser.tabs.unloadOnLowMemory", true);
// Keep fewer already-visited pages in memory for instant Back/Forward. (default -1: by RAM size)
user_pref("browser.sessionhistory.max_total_viewers", 2);
