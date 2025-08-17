# TinyOS Network

A class project for **CSE160 Computer Networks at UC Merced (Fall 2024)**.  
Implements a TinyOS application that simulates a basic computer network inside TOSSIM, with flooding, routing, and a lightweight TCP layer supporting a simple chatroom.

> **Team Size:** 2  
> **Timeline:** August 2024 – December 2024  
> **Tech:** TinyOS · nesC · TOSSIM · Docker

---

## Features
- **Flooding**: Disseminates messages across all nodes
- **Neighbor discovery**: Periodic beacon responses to track adjacency
- **Routing**:
  - Link-state
  - Distance vector
- **Transport**: Basic TCP-style connection with reliability
- **Application**: Chatroom built on top of TCP

---

## Getting Started

### Prerequisites
- Docker installed
- Clone of this repo

### Setup
1. Pull the TinyOS Docker image:
   ```bash
   docker pull ucmercedandeslab/tinyos_debian:latest
2. Load the code from this repository into a container created from that image.

## Run Simulation
1. Build with TinyOS:
   ```bash
   make micaz sim
2. Run the TOSSIM Python script:
   ```bash
   python TestSim.py

## Repository Structure
```bash
/dataStructures/    # Provided implementations of data structures like Hashmap and List
/includes/          # Type and struct definitions
/lib/               # The actual code implementing features like LSA and TCP
/noise/             # This is the "noise" of the network. A heavy noised network will cause issues with packet loss.
/topo/              # Example network topographies
```

## License
This project is licensed under the MIT License.
