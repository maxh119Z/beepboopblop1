import SwiftUI

struct CameraPoseView: View {
    @Environment(\.dismiss) var dismiss

    @State private var isLeftyMode = false
    @State private var isPoseReady = false
    @State private var openProb: Double? = nil

    @State private var elbow: OverlayDot? = nil
    @State private var shoulder: OverlayDot? = nil
    @State private var elbow2: OverlayDot? = nil
    @State private var shoulder2: OverlayDot? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // WebView camera feed + pose
                PoseWebView(
                    url: makePoseURL(),
                    onLandmarks: { pts in
                        updateOverlays(pts: pts, size: geo.size)
                        if !isPoseReady { isPoseReady = true }
                    },
                    onCnnProb: { p in
                        openProb = p
                    }
                )
                .ignoresSafeArea()

                // Loading text
                if !isPoseReady {
                    Text("Camera Loading")
                        .padding(12)
                        .background(.thinMaterial)
                        .cornerRadius(12)
                }

                // Top-left controls
                VStack {
                    HStack(spacing: 10) {
                        Button {
                            dismiss()
                        } label: {
                            Text("<")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 20)
                                .background(Color(hex: "#9fc9ae"))
                                .cornerRadius(12)
                        }

                        Button {
                            isLeftyMode.toggle()
                        } label: {
                            Text(isLeftyMode ? "L" : "R")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 20)
                                .background(Color(hex: "#c99fae"))
                                .cornerRadius(12)
                        }

                        if let p = openProb {
                            Text(String(format: "%.2f", p))
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 80, height: 50)
                                .background(.gray)
                                .cornerRadius(12)
                        }

                        Spacer()
                    }
                    .padding(.top, 50)
                    .padding(.leading, 20)

                    Spacer()
                }

                // Dots overlay
                if let d = elbow { DotView(dot: d) }
                if let d = shoulder { DotView(dot: d) }
                if let d = elbow2 { DotView(dot: d) }
                if let d = shoulder2 { DotView(dot: d) }
            }
        }
    }
}

private struct OverlayDot {
    let x: CGFloat
    let y: CGFloat
    let isGood: Bool
}

private struct DotView: View {
    let dot: OverlayDot
    var body: some View {
        Circle()
            .fill(dot.isGood ? Color(hex: "#0FFF50") : .red)
            .frame(width: 32, height: 32)
            .position(x: dot.x, y: dot.y)
    }
}

extension CameraPoseView {

    func makePoseURL() -> URL {
        // mirror your RN query params
        var comps = URLComponents(string: "https://beeppose.vercel.app/")!
        comps.queryItems = [
            .init(name: "enableSkeleton", value: "true"),
            .init(name: "enableKeyPoints", value: "true"),
            .init(name: "color", value: "255, 0, 0"),
            .init(name: "mode", value: "single"),
            .init(name: "scoreThreshold", value: "0.64"),
            .init(name: "isBackCamera", value: "false"),
            .init(name: "flipHorizontal", value: "false"),
            .init(name: "isFullScreen", value: "false"),
        ]
        return comps.url!
    }

    func updateOverlays(pts: [PosePoint], size: CGSize) {
        guard pts.count > 16 else { return }

        // indices same as your RN code
        let rs: PosePoint
        let ls: PosePoint
        let re: PosePoint
        let le: PosePoint
        let rw: PosePoint
        let lw: PosePoint

        if isLeftyMode {
            rs = pts[11]
            ls = pts[12]
            re = pts[13]
            le = pts[14]
            rw = pts[15]
            lw = pts[16]
        } else {
            rs = pts[12]
            ls = pts[11]
            re = pts[14]
            le = pts[13]
            rw = pts[16]
            lw = pts[15]
        }

        func vis(_ p: PosePoint) -> Double { p.visibility ?? 1.0 }
        guard [rs, ls, re, rw].allSatisfy({ vis($0) >= 0.6 }) else { return }

        // Map normalized -> screen coords (you used width - x*width)
        func screen(_ p: PosePoint) -> CGPoint {
            CGPoint(x: size.width - CGFloat(p.x) * size.width,
                    y: CGFloat(p.y) * size.height)
        }

        // Vector helpers
        func vec(_ a: PosePoint, _ b: PosePoint) -> (Double, Double) { (a.x - b.x, a.y - b.y) }
        func dot(_ u: (Double, Double), _ v: (Double, Double)) -> Double { u.0*v.0 + u.1*v.1 }
        func mag(_ u: (Double, Double)) -> Double { sqrt(u.0*u.0 + u.1*u.1) }
        func angleDeg(_ u: (Double, Double), _ v: (Double, Double)) -> Double {
            let denom = mag(u) * mag(v)
            if denom == 0 { return 0 }
            let c = max(-1, min(1, dot(u, v)/denom))
            return acos(c) * 180 / .pi
        }

        // --- Non-dominant shoulder angle (ndDEGREESD) ---
        let lrshoulder = vec(rs, ls)     // rs - ls
        let ellshoulder = vec(ls, le)    // ls - le
        var ndD = angleDeg(lrshoulder, ellshoulder)

        let nslope1 = (rs.y - ls.y) / (rs.x - ls.x)
        let nslope2 = (le.y - ls.y) / (le.x - ls.x)
        if nslope2 >= nslope1 { ndD *= -1 }

        let shoulder2Pt = screen(ls)
        let shoulder2Good = isLeftyMode
            ? !(ndD < -31.3 || ndD > 16.7)
            : !(ndD < -10 || ndD > 30)
        shoulder2 = .init(x: shoulder2Pt.x, y: shoulder2Pt.y, isGood: shoulder2Good)

        // --- Non-dominant elbow angle (ndDEGREESC) ---
        let lewrist = vec(lw, le)  // lw - le
        let ndC = angleDeg(lewrist, ellshoulder)
        let elbow2Pt = screen(le)
        // This dot also depends on dominant elbow angle later, so set after we compute both.
        // We'll compute dominant first then finalize.

        // --- Dominant elbow angle (DEGREESC) ---
        let elshoulder = vec(rs, re)  // rs - re
        let rewrist = vec(rw, re)     // rw - re
        let C = angleDeg(rewrist, elshoulder)
        let elbowPt = screen(re)
        let elbowGood = !(C < 35.0 || C > 98.1)
        elbow = .init(x: elbowPt.x, y: elbowPt.y, isGood: elbowGood)

        // --- Dominant shoulder angle (DEGREESD) ---
        let rlshoulder = vec(ls, rs)  // ls - rs
        var D = angleDeg(rlshoulder, elshoulder)

        let slope1 = (ls.y - rs.y) / (ls.x - rs.x)
        let slope2 = (re.y - rs.y) / (re.x - rs.x)
        if slope2 < slope1 { D *= -1 }

        let shoulderPt = screen(rs)
        let shoulderGood = isLeftyMode
            ? !(D < -10 || D > 30)
            : !(D < -31.3 || D > 16.7)
        shoulder = .init(x: shoulderPt.x, y: shoulderPt.y, isGood: shoulderGood)

        // --- finalize elbow2 rule uses C + ndC ---
        let elbow2Good = !(ndC < 90 || ndC > 180 || ndC + C < 120 || ndC + C > 240)
        elbow2 = .init(x: elbow2Pt.x, y: elbow2Pt.y, isGood: elbow2Good)
    }
}
