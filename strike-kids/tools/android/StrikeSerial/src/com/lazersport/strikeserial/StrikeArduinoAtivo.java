package com.lazersport.strikeserial;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

/**
 * PERMISSÃO DO ARDUINO UMA VEZ SÓ.
 *
 * Com este filtro (res/xml/strike_usb_arduino.xml) a janela de permissão
 * USB do Android mostra a caixa "Usar por padrão": marcada uma vez, a
 * permissão fica guardada (inclusive depois de desligar a TV Box), e ao
 * encaixar o Arduino o Android já abre o jogo. Esta atividade invisível só
 * traz o jogo para a frente e fecha na hora.
 */
public class StrikeArduinoAtivo extends Activity {
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
