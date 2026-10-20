package com.lazersport.strikecamera;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

/**
 * PERMISSÃO DA WEBCAM USB UMA VEZ SÓ (igual ao jogo de soco).
 *
 * Quando a webcam é encaixada, o Android pergunta "Abrir o Strike Kids
 * quando este dispositivo USB for conectado?" com a caixa "Usar por padrão".
 * Marcada uma vez, a permissão fica guardada para sempre (inclusive depois
 * de desligar a TV Box). Esta atividade invisível só traz o jogo para a
 * frente e fecha na hora.
 */
public class StrikeUsbAtivo extends Activity {
	@Override
	protected void onCreate(Bundle estado) {
		super.onCreate(estado);
		try {
			Intent jogo = getPackageManager().getLaunchIntentForPackage(getPackageName());
			if (jogo != null) {
				jogo.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
				startActivity(jogo);
			}
		} catch (Throwable ignored) {
		}
		finish();
	}
}
