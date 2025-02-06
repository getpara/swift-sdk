//
//  WalletsView.swift
//  example
//
//  Created by Brian Corbin on 2/6/25.
//

import SwiftUI
import ParaSwift

struct WalletsView: View {
    @EnvironmentObject var paraManager: ParaManager
    
    @State private var selectedWalletType: WalletType = .evm
    
    var body: some View {
        NavigationStack {
            VStack {
                Picker("Select Wallet Type", selection: $selectedWalletType) {
                    Text("EVM").tag("EVM")
                    Text("Solana").tag("SOLANA")
                    Text("Cosmos").tag("COSMOS")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                List(paraManager.wallets.filter({ $0.type == selectedWalletType }), id: \.id) { wallet in
                    NavigationLink {
                        WalletView(selectedWallet: wallet)
                    } label: {
                        Text(wallet.address ?? "unknown")
                    }
                }
            }
            .navigationTitle("Wallets")
            .toolbar { Button("Create") {
                print("New wallet")
            }}
        }
    }
}
