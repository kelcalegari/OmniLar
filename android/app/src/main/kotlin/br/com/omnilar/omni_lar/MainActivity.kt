package br.com.omnilar.omni_lar

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth exige FragmentActivity para exibir o prompt de biometria/PIN.
// Com FlutterActivity o plugin lança "no_fragment_activity" e toda
// confirmação de segurança (liquidação, perdão, renegociação) falha.
class MainActivity : FlutterFragmentActivity()
