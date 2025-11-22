import SwiftUI

struct SplashView: View {
    @State private var opacity = 0.0
    @State private var scale = 0.8
    @State private var logoOpacity = 0.0
    @State private var logoScale = 0.5
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.15, green: 0.25, blue: 0.45),
                    Color(red: 0.08, green: 0.18, blue: 0.35)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // App logo/branding area
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 120, height: 120)
                        .opacity(logoOpacity)
                        .scaleEffect(logoScale)
                    
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 60, weight: .thin))
                        .foregroundColor(.white)
                        .opacity(logoOpacity)
                        .scaleEffect(logoScale)
                }
                
                // App name with animation
                VStack(spacing: 10) {
                    Text("budjetlens")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .opacity(opacity)
                        .scaleEffect(scale)
                        .shadow(color: .white.opacity(0.3), radius: 10, x: 0, y: 5)
                    
                    Text("Manage your finances with clarity")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .opacity(opacity)
                        .scaleEffect(scale)
                }
                
                // Loading indicator
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
                
                Text("Loading your financial insights...")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7, blendDuration: 0.8).delay(0.2)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7, blendDuration: 0.8).delay(0.5)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
}

struct AnimatedSplashView: View {
    @State private var isAnimating = false
    @State private var opacity = 0.0
    @State private var scale = 0.5
    @State private var textOpacity = 0.0
    @State private var textScale = 0.8
    @State private var showLoading = false
    
    var body: some View {
        ZStack {
            // Dynamic gradient background
            ZStack {
                // Base gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.1, green: 0.2, blue: 0.4),
                        Color(red: 0.15, green: 0.25, blue: 0.45),
                        Color(red: 0.08, green: 0.18, blue: 0.35)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // Animated floating shapes
                GeometryReader { geometry in
                    ZStack {
                        ForEach(0..<8) { index in
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.white.opacity(0.1), Color.blue.opacity(0.05)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: CGFloat.random(in: 20...60), height: CGFloat.random(in: 20...60))
                                .position(
                                    x: CGFloat.random(in: 0...geometry.size.width),
                                    y: CGFloat.random(in: 0...geometry.size.height)
                                )
                                .opacity(0.3)
                                .animation(
                                    Animation.linear(duration: Double.random(in: 15...25))
                                        .repeatForever(autoreverses: false)
                                        .delay(Double.random(in: 0...5)),
                                    value: isAnimating
                                )
                                .onAppear {
                                    if index == 0 { startAnimation()
                                    }
                                }
                        }
                    }
                }
            }
            
            VStack(spacing: 40) {
                // Main logo container with pulsing animation
                ZStack {
                    // Outer glow ring
                    Circle()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 160, height: 160)
                        .blur(radius: 10)
                        .opacity(0.7)
                        .scaleEffect(1.2)
                    
                    // Main circle
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue.opacity(0.9), Color.purple.opacity(0.9)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)
                        .overlay(
                            Circle()
                                .stroke(LinearGradient(
                                    gradient: Gradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0.05)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ), lineWidth: 2)
                        )
                        .shadow(color: Color.blue.opacity(0.5), radius: 20, x: 0, y: 0)
                        .scaleEffect(scale)
                        .animation(
                            Animation.easeInOut(duration: 2)
                                .repeatForever(autoreverses: true)
                                .delay(0.3),
                            value: isAnimating
                        )
                    
                    // App icon
                    Image(systemName: "chart.bar.doc.horizontal.fill")
                        .font(.system(size: 70, weight: .thin))
                        .foregroundColor(.white)
                        .opacity(textOpacity)
                        .scaleEffect(textScale)
                        .shadow(color: .white.opacity(0.5), radius: 5)
                }
                
                // App name with wave animation
                VStack(spacing: 15) {
                    HStack(spacing: 2) {
                        ForEach("budjetlens".map { String($0) }, id: \.self) { letter in
                            Text(letter)
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .opacity(textOpacity)
                                .scaleEffect(textScale)
                                .animation(
                                    Animation.spring(response: 0.6, dampingFraction: 0.5)
                                        .delay(Double.random(in: 0...1)),
                                    value: isAnimating
                                )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    
                    Text("Smart Financial Management")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .opacity(textOpacity)
                        .padding(.horizontal)
                }
                
                // Animated loading section
                VStack(spacing: 15) {
                    ZStack {
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 8)
                        
                        Capsule()
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.purple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: showLoading ? 120 : 0, height: 8)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: showLoading)
                    }
                    
                    HStack {
                        Circle()
                            .fill(Color.blue.opacity(0.8))
                            .frame(width: 8, height: 8)
                            .scaleEffect(showLoading ? 1.5 : 0.8)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: showLoading)
                        
                        Circle()
                            .fill(Color.purple.opacity(0.8))
                            .frame(width: 8, height: 8)
                            .scaleEffect(showLoading ? 1.0 : 0.8)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(0.2), value: showLoading)
                        
                        Circle()
                            .fill(Color.blue.opacity(0.8))
                            .frame(width: 8, height: 8)
                            .scaleEffect(showLoading ? 1.5 : 0.8)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(0.4), value: showLoading)
                    }
                    .padding(.top, 5)
                    
                    Text("Analyzing your financial data...")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .opacity(textOpacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        withAnimation(.easeOut(duration: 0.8)) {
            scale = 1.1
            textScale = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                textOpacity = 1.0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    showLoading = true
                }
            }
        }

        // Start the continuous animation
        isAnimating = true
    }

}

struct SplashView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SplashView()
                .previewInterfaceOrientation(.portrait)
            
            AnimatedSplashView()
                .previewInterfaceOrientation(.portrait)
        }
    }
}