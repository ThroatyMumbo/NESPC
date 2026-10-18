// map_hub -- NES 2.0 mapper 773: Desk, a 6502-native desktop.

module map_hub(
	input  MapIn mai,
	output MapOut mao
);

	assign mao = mai.cfg.map_idx == 773 ? map_out_desk : map_out_nom;

	MapOut map_out_desk;
	map_desk mdesk(mai, map_out_desk);

	MapOut map_out_nom;
	map_nom mnom(mai, map_out_nom);

endmodule
