document.addEventListener("DOMContentLoaded", () => {
    const list = document.getElementById("network-list");
    const ssidInput = document.getElementById("ssid");
    const passwordInput = document.getElementById("password");

    function fetchNetworks() {
        list.innerHTML = '<div class="loading-spinner"></div>';
        fetch("/access-points.json")
            .then(response => {
                if (!response.ok) throw new Error("Network response was not ok");
                return response.json();
            })
            .then(data => {
                list.innerHTML = "";
                if (data.length === 0) {
                    list.innerHTML = "<p>No networks found.</p>";
                    return;
                }
                data.forEach(network => {
                    const div = document.createElement("div");
                    div.className = "network-item";

                    const ssidSpan = document.createElement("span");
                    ssidSpan.className = "network-ssid";
                    ssidSpan.textContent = network.ssid;

                    const rssiSpan = document.createElement("span");
                    rssiSpan.className = "network-rssi";
                    rssiSpan.textContent = `${network.rssi} dBm`;

                    div.appendChild(ssidSpan);
                    div.appendChild(rssiSpan);

                    div.addEventListener("click", () => {
                        ssidInput.value = network.ssid;
                        passwordInput.focus();
                    });

                    list.appendChild(div);
                });
            })
            .catch(error => {
                console.error("Failed to fetch networks:", error);
                list.innerHTML = "<p>Error loading networks. Please reload.</p>";
            });
    }

    const refreshBtn = document.getElementById("refresh-btn");
    if (refreshBtn) {
        refreshBtn.addEventListener("click", fetchNetworks);
    }

    fetchNetworks();
});
