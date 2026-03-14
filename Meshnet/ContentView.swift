import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var manager = MultipeerManager()
    @State private var messageText = ""
    @State private var showingSettings = false
    @State private var viewMode = 0 // 0: Chat, 1: Radar

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Circle().fill(manager.connectedPeers.isEmpty ? Color.red : Color.green).frame(width: 8, height: 8)
                    Text("\(manager.connectedPeers.count) Nodes Online").font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Picker("", selection: $viewMode) {
                        Image(systemName: "bubble.left.and.bubble.right").tag(0)
                        Image(systemName: "dot.radiowaves.up.forward").tag(1)
                    }.pickerStyle(SegmentedPickerStyle()).frame(width: 100)
                }.padding(.horizontal)

                Divider().padding(.top, 4)

                if viewMode == 0 {
                    chatView
                } else {
                    radarView
                }
            }
            .navigationTitle("Disaster Mesh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Clear") { manager.clearHistory() }.foregroundColor(.red) }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { manager.restartSession() }) { Image(systemName: "arrow.clockwise") }
                    Button(action: { showingSettings.toggle() }) { Image(systemName: "gearshape.fill") }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView(manager: manager, isPresented: $showingSettings) }
        }
    }

    private var chatView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(manager.messages) { MessageBubble(message: $0, manager: manager) }
                    }.padding()
                }
                .onChange(of: manager.messages) { _, newValue in
                    if let last = newValue.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            inputBar
        }
    }

    private var radarView: some View {
        VStack {
            Spacer()
            RadarView(manager: manager)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .padding(30)
            Text("Range: 500m").font(.caption).foregroundColor(.secondary)
            Spacer()
        }.background(Color.black.opacity(0.05))
    }

    private var inputBar: some View {
        HStack {
            TextField("Emergency Message...", text: $messageText).textFieldStyle(RoundedBorderTextFieldStyle())
            Button(action: {
                let trimmed = messageText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { manager.sendMessage(text: trimmed); messageText = "" }
            }) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24)).foregroundColor(manager.connectedPeers.isEmpty ? .gray : .orange)
            }.disabled(manager.connectedPeers.isEmpty)
        }.padding().background(Color(UIColor.systemGray6))
    }
}

// MARK: - Subviews
struct MessageBubble: View {
    let message: LocalMessage
    @ObservedObject var manager: MultipeerManager

    var body: some View {
        HStack {
            if message.isMe { Spacer() }
            VStack(alignment: message.isMe ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(message.senderName).font(.caption2).bold()
                    if message.isRelayed { Image(systemName: "network").font(.system(size: 8)).foregroundColor(.orange) }
                }
                Text(message.content).padding(10).background(message.isMe ? Color.blue : Color(UIColor.systemGray5))
                    .foregroundColor(message.isMe ? .white : .primary).cornerRadius(12)
                
                if let lat = message.latitude, let lon = message.longitude {
                    ProximityArrow(targetLat: lat, targetLon: lon, manager: manager)
                }
            }
            if !message.isMe { Spacer() }
        }
    }
}

struct ProximityArrow: View {
    let targetLat: Double
    let targetLon: Double
    @ObservedObject var manager: MultipeerManager

    var body: some View {
        if let myLoc = manager.lastLocation {
            let targetLoc = CLLocation(latitude: targetLat, longitude: targetLon)
            let distance = myLoc.distance(from: targetLoc)
            let bearing = myLoc.bearing(to: targetLoc)
            let rotation = bearing - manager.currentHeading

            HStack(spacing: 4) {
                Image(systemName: "location.north.fill")
                    .rotationEffect(.degrees(rotation))
                    .foregroundColor(.orange)
                Text(distance < 1000 ? "\(Int(distance))m" : String(format: "%.1fkm", distance/1000))
            }.font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
        }
    }
}

struct RadarView: View {
    @ObservedObject var manager: MultipeerManager
    let range: Double = 500

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width/2, y: geo.size.height/2)
            let radius = min(geo.size.width, geo.size.height) / 2
            ZStack {
                Circle().stroke(Color.green.opacity(0.2), lineWidth: 1)
                Circle().stroke(Color.green.opacity(0.1), lineWidth: 1).scaleEffect(0.5)
                
                ForEach(Array(manager.peerRegistry.values)) { peer in
                    if let lat = peer.latitude, let lon = peer.longitude, let myLoc = manager.lastLocation {
                        let target = CLLocation(latitude: lat, longitude: lon)
                        let dist = min(myLoc.distance(from: target) / range, 1.0) * radius
                        let angle = (myLoc.bearing(to: target) - manager.currentHeading) * .pi / 180
                        
                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                            .position(x: center.x + CGFloat(sin(angle) * dist), y: center.y - CGFloat(cos(angle) * dist))
                    }
                }
                Image(systemName: "location.north.fill").foregroundColor(.blue)
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var manager: MultipeerManager
    @Binding var isPresented: Bool
    var body: some View {
        NavigationView {
            Form { Section(header: Text("Identify Yourself")) { TextField("Username", text: $manager.username) } }
            .navigationTitle("Settings").toolbar { Button("Done") { isPresented = false } }
        }
    }
}
